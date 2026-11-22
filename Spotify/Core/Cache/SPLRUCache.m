//
//  SPLRUCache.m
//  Spotify
//

#import "SPLRUCache.h"
#import <os/lock.h>

@interface SPLRUNode : NSObject
@property (nonatomic, strong) id key;
@property (nonatomic, strong) id value;
@property (nonatomic, assign) NSUInteger cost;
@property (nonatomic, weak, nullable) SPLRUNode *prev;
@property (nonatomic, strong, nullable) SPLRUNode *next;
@end

@implementation SPLRUNode
@end

@interface SPLRUCache () {
    os_unfair_lock _lock;
}
@property (nonatomic, assign) NSUInteger maxCount;
@property (nonatomic, assign) NSUInteger maxCost;
@property (nonatomic, assign) NSUInteger totalCost;
@property (nonatomic, assign) NSUInteger hitCount;
@property (nonatomic, assign) NSUInteger missCount;
@property (nonatomic, strong) NSMutableDictionary *map;
@property (nonatomic, strong, nullable) SPLRUNode *head;
@property (nonatomic, strong, nullable) SPLRUNode *tail;
@end

@implementation SPLRUCache

- (instancetype)initWithMaxCount:(NSUInteger)maxCount {
    return [self initWithMaxCount:maxCount maxCost:NSUIntegerMax];
}

- (instancetype)initWithMaxCount:(NSUInteger)maxCount maxCost:(NSUInteger)maxCost {
    if (self = [super init]) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _maxCount = MAX(maxCount, 1);
        _maxCost = MAX(maxCost, 1);
        _trimsOnMemoryWarning = YES;
        _map = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleMemoryWarning)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleMemoryWarning {
    if (!self.trimsOnMemoryWarning) return;
    NSUInteger target = self.count / 2;
    [self trimToCount:target];
}

#pragma mark - Linked List (Caller holds lock)

- (void)moveToHead:(SPLRUNode *)node {
    if (node == self.head) return;
    [self unlinkNode:node];
    [self insertAtHead:node];
}

- (void)insertAtHead:(SPLRUNode *)node {
    node.prev = nil;
    node.next = self.head;
    if (self.head) self.head.prev = node;
    self.head = node;
    if (!self.tail) self.tail = node;
}

- (void)unlinkNode:(SPLRUNode *)node {
    SPLRUNode *prev = node.prev;
    SPLRUNode *next = node.next;
    if (prev) prev.next = next; else self.head = next;
    if (next) next.prev = prev; else self.tail = prev;
    node.prev = nil;
    node.next = nil;
}

- (nullable SPLRUNode *)popTail {
    SPLRUNode *node = self.tail;
    if (!node) return nil;
    [self unlinkNode:node];
    [self.map removeObjectForKey:node.key];
    self.totalCost = (self.totalCost >= node.cost) ? (self.totalCost - node.cost) : 0;
    return node;
}

#pragma mark - Public API

- (NSUInteger)count {
    os_unfair_lock_lock(&_lock);
    NSUInteger c = self.map.count;
    os_unfair_lock_unlock(&_lock);
    return c;
}

- (id)objectForKey:(id)key {
    if (!key) return nil;
    os_unfair_lock_lock(&_lock);
    SPLRUNode *node = self.map[key];
    id val = nil;
    if (node) {
        [self moveToHead:node];
        self.hitCount += 1;
        val = node.value;
    } else {
        self.missCount += 1;
    }
    os_unfair_lock_unlock(&_lock);
    return val;
}

- (id)peekObjectForKey:(id)key {
    if (!key) return nil;
    os_unfair_lock_lock(&_lock);
    SPLRUNode *node = self.map[key];
    id val = node.value;
    os_unfair_lock_unlock(&_lock);
    return val;
}

- (void)setObject:(id)object forKey:(id)key {
    [self setObject:object forKey:key cost:0];
}

- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost {
    if (!key) return;
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }

    NSMutableArray<SPLRUNode *> *evicted = nil;

    os_unfair_lock_lock(&_lock);
    SPLRUNode *existing = self.map[key];
    if (existing) {
        self.totalCost = (self.totalCost >= existing.cost) ? (self.totalCost - existing.cost) : 0;
        existing.value = object;
        existing.cost = cost;
        self.totalCost += cost;
        [self moveToHead:existing];
    } else {
        SPLRUNode *node = [SPLRUNode new];
        node.key = [key conformsToProtocol:@protocol(NSCopying)] ? [key copy] : key;
        node.value = object;
        node.cost = cost;
        self.map[node.key] = node;
        self.totalCost += cost;
        [self insertAtHead:node];
    }

    while (self.map.count > self.maxCount || (self.map.count > 0 && self.totalCost > self.maxCost)) {
        SPLRUNode *removed = [self popTail];
        if (!removed) break;
        if (self.evictionHandler) {
            if (!evicted) evicted = [NSMutableArray array];
            [evicted addObject:removed];
        }
    }
    os_unfair_lock_unlock(&_lock);

    for (SPLRUNode *node in evicted) {
        self.evictionHandler(node.key, node.value);
    }
}

- (void)removeObjectForKey:(id)key {
    if (!key) return;
    os_unfair_lock_lock(&_lock);
    SPLRUNode *node = self.map[key];
    if (node) {
        [self unlinkNode:node];
        [self.map removeObjectForKey:key];
        self.totalCost = (self.totalCost >= node.cost) ? (self.totalCost - node.cost) : 0;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)removeAllObjects {
    os_unfair_lock_lock(&_lock);
    [self.map removeAllObjects];
    self.head = nil;
    self.tail = nil;
    self.totalCost = 0;
    os_unfair_lock_unlock(&_lock);
}

- (void)trimToCount:(NSUInteger)targetCount {
    NSMutableArray<SPLRUNode *> *evicted = nil;
    os_unfair_lock_lock(&_lock);
    while (self.map.count > targetCount) {
        SPLRUNode *removed = [self popTail];
        if (!removed) break;
        if (self.evictionHandler) {
            if (!evicted) evicted = [NSMutableArray array];
            [evicted addObject:removed];
        }
    }
    os_unfair_lock_unlock(&_lock);

    for (SPLRUNode *node in evicted) {
        self.evictionHandler(node.key, node.value);
    }
}

- (NSArray *)allKeysInMRUOrder {
    NSMutableArray *keys = [NSMutableArray array];
    os_unfair_lock_lock(&_lock);
    SPLRUNode *cursor = self.head;
    while (cursor) {
        [keys addObject:cursor.key];
        cursor = cursor.next;
    }
    os_unfair_lock_unlock(&_lock);
    return [keys copy];
}

@end
