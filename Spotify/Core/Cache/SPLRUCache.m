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

@synthesize totalCost = _totalCost;
@synthesize hitCount = _hitCount;
@synthesize missCount = _missCount;

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
    _totalCost = (_totalCost >= node.cost) ? (_totalCost - node.cost) : 0;
    return node;
}

#pragma mark - Public API

- (NSUInteger)count {
    os_unfair_lock_lock(&_lock);
    NSUInteger c = self.map.count;
    os_unfair_lock_unlock(&_lock);
    return c;
}

- (NSUInteger)totalCost {
    os_unfair_lock_lock(&_lock);
    NSUInteger v = _totalCost;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (NSUInteger)hitCount {
    os_unfair_lock_lock(&_lock);
    NSUInteger v = _hitCount;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (NSUInteger)missCount {
    os_unfair_lock_lock(&_lock);
    NSUInteger v = _missCount;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (id)objectForKey:(id)key {
    if (!key) return nil;
    os_unfair_lock_lock(&_lock);
    SPLRUNode *node = self.map[key];
    id val = nil;
    if (node) {
        [self moveToHead:node];
        _hitCount += 1;
        val = node.value;
    } else {
        _missCount += 1;
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
    void (^handler)(id, id) = nil;

    os_unfair_lock_lock(&_lock);
    handler = self.evictionHandler;
    SPLRUNode *existing = self.map[key];
    if (existing) {
        _totalCost = (_totalCost >= existing.cost) ? (_totalCost - existing.cost) : 0;
        existing.value = object;
        existing.cost = cost;
        _totalCost += cost;
        [self moveToHead:existing];
    } else {
        SPLRUNode *node = [SPLRUNode new];
        node.key = [key conformsToProtocol:@protocol(NSCopying)] ? [key copy] : key;
        node.value = object;
        node.cost = cost;
        self.map[node.key] = node;
        _totalCost += cost;
        [self insertAtHead:node];
    }

    while (self.map.count > self.maxCount || (self.map.count > 0 && _totalCost > self.maxCost)) {
        SPLRUNode *removed = [self popTail];
        if (!removed) break;
        if (handler) {
            if (!evicted) evicted = [NSMutableArray array];
            [evicted addObject:removed];
        }
    }
    os_unfair_lock_unlock(&_lock);

    if (handler) {
        for (SPLRUNode *node in evicted) {
            handler(node.key, node.value);
        }
    }
}

- (void)removeObjectForKey:(id)key {
    if (!key) return;
    os_unfair_lock_lock(&_lock);
    SPLRUNode *node = self.map[key];
    if (node) {
        [self unlinkNode:node];
        [self.map removeObjectForKey:key];
        _totalCost = (_totalCost >= node.cost) ? (_totalCost - node.cost) : 0;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)removeAllObjects {
    os_unfair_lock_lock(&_lock);
    [self.map removeAllObjects];
    self.head = nil;
    self.tail = nil;
    _totalCost = 0;
    os_unfair_lock_unlock(&_lock);
}

- (void)trimToCount:(NSUInteger)targetCount {
    NSMutableArray<SPLRUNode *> *evicted = nil;
    void (^handler)(id, id) = nil;
    os_unfair_lock_lock(&_lock);
    handler = self.evictionHandler;
    while (self.map.count > targetCount) {
        SPLRUNode *removed = [self popTail];
        if (!removed) break;
        if (handler) {
            if (!evicted) evicted = [NSMutableArray array];
            [evicted addObject:removed];
        }
    }
    os_unfair_lock_unlock(&_lock);

    if (handler) {
        for (SPLRUNode *node in evicted) {
            handler(node.key, node.value);
        }
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
