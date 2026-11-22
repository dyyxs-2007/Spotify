//
//  SPLRUCache.h
//  Spotify
//
//  线程安全的 O(1) 双向链表 + 哈希表 LRU 缓存容器。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPLRUCache<KeyType, ObjectType> : NSObject

@property (nonatomic, assign, readonly) NSUInteger maxCount;
@property (nonatomic, assign, readonly) NSUInteger maxCost;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign, readonly) NSUInteger totalCost;
@property (nonatomic, assign, readonly) NSUInteger hitCount;
@property (nonatomic, assign, readonly) NSUInteger missCount;

/// 收到系统内存警告时是否自动释放一半条目（纯内存缓存建议 YES，磁盘索引建议 NO）
@property (nonatomic, assign) BOOL trimsOnMemoryWarning;

/// 元素被 LRU 淘汰时在当前线程触发（已在锁外回调，可安全重入）
@property (nonatomic, copy, nullable) void (^evictionHandler)(KeyType key, ObjectType object);

- (instancetype)initWithMaxCount:(NSUInteger)maxCount maxCost:(NSUInteger)maxCost;
- (instancetype)initWithMaxCount:(NSUInteger)maxCount;

- (nullable ObjectType)objectForKey:(KeyType)key;
/// 读取但不计入命中统计、不改变 MRU 顺序（用于内部探测）
- (nullable ObjectType)peekObjectForKey:(KeyType)key;

- (void)setObject:(ObjectType)object forKey:(KeyType)key;
- (void)setObject:(ObjectType)object forKey:(KeyType)key cost:(NSUInteger)cost;

- (void)removeObjectForKey:(KeyType)key;
- (void)removeAllObjects;
- (void)trimToCount:(NSUInteger)targetCount;

/// 按最近使用顺序（MRU -> LRU）返回所有 key
- (NSArray<KeyType> *)allKeysInMRUOrder;

@end

NS_ASSUME_NONNULL_END
