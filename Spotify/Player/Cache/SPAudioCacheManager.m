//
//  SPAudioCacheManager.m
//  Spotify
//

#import "SPAudioCacheManager.h"
#import "SPLRUCache.h"
#import "SPMusicRepository.h"

static const NSUInteger SPAudioL1AssetMaxCount = 6;
static const NSUInteger SPAudioL1URLMaxCount = 64;
static const NSUInteger SPAudioL2DiskMaxCount = 40;
static const NSUInteger SPAudioL2DiskMaxBytes = 200 * 1024 * 1024; // 200 MB
static const NSTimeInterval SPAudioURLCacheTTL = 15 * 60.0;        // 15 分钟 URL 有效期

@interface SPCachedRemoteURL : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) CFAbsoluteTime cachedAt;
@end

@implementation SPCachedRemoteURL
@end

@interface SPAudioCacheManager ()
@property (nonatomic, strong) SPLRUCache<NSString *, SPCachedRemoteURL *> *resolvedURLCache;
@property (nonatomic, strong) SPLRUCache<NSString *, AVURLAsset *> *assetCache;
@property (nonatomic, strong) SPLRUCache<NSString *, NSNumber *> *diskIndexCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *diskFileNames;

@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *manifestPath;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, strong) NSURLSession *downloadSession;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *activeDownloads;

@property (nonatomic, assign) NSUInteger totalHitCount;
@property (nonatomic, assign) NSUInteger totalRequestCount;
@end

@implementation SPAudioCacheManager

+ (instancetype)shared {
    static SPAudioCacheManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SPAudioCacheManager new]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _ioQueue = dispatch_queue_create("com.dyyxs.spotify.audiocache.io", DISPATCH_QUEUE_SERIAL);
        _activeDownloads = [NSMutableDictionary dictionary];
        _diskFileNames = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 20;
        config.HTTPMaximumConnectionsPerHost = 3;
        _downloadSession = [NSURLSession sessionWithConfiguration:config];

        _resolvedURLCache = [[SPLRUCache alloc] initWithMaxCount:SPAudioL1URLMaxCount];
        _assetCache = [[SPLRUCache alloc] initWithMaxCount:SPAudioL1AssetMaxCount];

        _diskIndexCache = [[SPLRUCache alloc] initWithMaxCount:SPAudioL2DiskMaxCount maxCost:SPAudioL2DiskMaxBytes];
        _diskIndexCache.trimsOnMemoryWarning = NO;

        NSString *cachesDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        _cacheDirectory = [cachesDir stringByAppendingPathComponent:@"SPAudioCache"];
        _manifestPath = [_cacheDirectory stringByAppendingPathComponent:@"manifest.json"];

        __weak typeof(self) weakSelf = self;
        _diskIndexCache.evictionHandler = ^(NSString *key, NSNumber *size) {
            [weakSelf deleteDiskFileForSafeKey:key];
        };

        [self setupDiskCache];
    }
    return self;
}

#pragma mark - Stats

- (NSUInteger)diskCacheBytes { return self.diskIndexCache.totalCost; }
- (NSUInteger)diskCachedTrackCount { return self.diskIndexCache.count; }
- (NSUInteger)memoryAssetCount { return self.assetCache.count; }
- (NSUInteger)resolvedURLCount { return self.resolvedURLCache.count; }

#pragma mark - Extension & URL TTL Helpers

+ (NSSet<NSString *> *)supportedAudioExtensions {
    static NSSet<NSString *> *exts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exts = [NSSet setWithObjects:@"mp3", @"m4a", @"aac", @"wav", @"flac", nil];
    });
    return exts;
}

- (NSString *)audioExtensionForRemoteURL:(NSURL *)url {
    NSString *ext = url.pathExtension.lowercaseString;
    if ([[SPAudioCacheManager supportedAudioExtensions] containsObject:ext]) {
        return ext;
    }
    return @"mp3";
}

- (nullable NSURL *)validCachedURLForSafeKey:(NSString *)safeKey peekOnly:(BOOL)peekOnly {
    SPCachedRemoteURL *entry = peekOnly ? [self.resolvedURLCache peekObjectForKey:safeKey] : [self.resolvedURLCache objectForKey:safeKey];
    if (!entry) return nil;
    if ((CFAbsoluteTimeGetCurrent() - entry.cachedAt) >= SPAudioURLCacheTTL) {
        [self.resolvedURLCache removeObjectForKey:safeKey];
        [self.assetCache removeObjectForKey:safeKey];
        return nil;
    }
    return entry.url;
}

- (void)cacheRemoteURL:(NSURL *)url forSafeKey:(NSString *)safeKey {
    SPCachedRemoteURL *entry = [SPCachedRemoteURL new];
    entry.url = url;
    entry.cachedAt = CFAbsoluteTimeGetCurrent();
    [self.resolvedURLCache setObject:entry forKey:safeKey cost:1];
}

#pragma mark - Disk Setup & Manifest

- (void)setupDiskCache {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectory]) {
        [fm createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:self.cacheDirectory error:nil];
    NSSet<NSString *> *exts = [SPAudioCacheManager supportedAudioExtensions];
    NSMutableDictionary<NSString *, NSString *> *scannedFiles = [NSMutableDictionary dictionary];

    for (NSString *name in contents) {
        if ([name hasSuffix:@".tmp"]) {
            [fm removeItemAtPath:[self.cacheDirectory stringByAppendingPathComponent:name] error:nil];
            continue;
        }
        NSString *ext = name.pathExtension.lowercaseString;
        if ([exts containsObject:ext]) {
            NSString *safeKey = [name stringByDeletingPathExtension];
            scannedFiles[safeKey] = name;
        }
    }

    @synchronized (self.diskFileNames) {
        [self.diskFileNames addEntriesFromDictionary:scannedFiles];
    }

    // 从 manifest.json 恢复 MRU 顺序
    NSData *manifestData = [NSData dataWithContentsOfFile:self.manifestPath];
    NSArray<NSString *> *mruKeys = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil] : nil;
    if ([mruKeys isKindOfClass:NSArray.class]) {
        for (NSString *safeKey in [mruKeys reverseObjectEnumerator]) {
            if (![safeKey isKindOfClass:NSString.class]) continue;
            NSString *filePath = [self existingFilePathForSafeKey:safeKey];
            if (!filePath) continue;
            unsigned long long size = [[fm attributesOfItemAtPath:filePath error:nil] fileSize];
            if (size > 0) {
                [self.diskIndexCache setObject:@(size) forKey:safeKey cost:(NSUInteger)size];
            }
        }
    }

    // 补充扫描目录中未写入 manifest 的音频文件
    for (NSString *safeKey in scannedFiles) {
        if (![self.diskIndexCache peekObjectForKey:safeKey]) {
            NSString *filePath = [self.cacheDirectory stringByAppendingPathComponent:scannedFiles[safeKey]];
            unsigned long long size = [[fm attributesOfItemAtPath:filePath error:nil] fileSize];
            if (size > 0) {
                [self.diskIndexCache setObject:@(size) forKey:safeKey cost:(NSUInteger)size];
            }
        }
    }
}

- (void)persistManifestAsync {
    NSArray<NSString *> *keys = [self.diskIndexCache allKeysInMRUOrder];
    NSString *path = self.manifestPath;
    dispatch_async(self.ioQueue, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:keys options:0 error:nil];
        if (data) [data writeToFile:path atomically:YES];
    });
}

- (void)deleteDiskFileForSafeKey:(NSString *)safeKey {
    NSString *path = [self existingFilePathForSafeKey:safeKey];
    @synchronized (self.diskFileNames) {
        [self.diskFileNames removeObjectForKey:safeKey];
    }
    if (path) {
        dispatch_async(self.ioQueue, ^{
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        });
    }
    [self persistManifestAsync];
}

- (NSString *)safeKeyForTrackId:(NSString *)trackId {
    if (trackId.length == 0) return @"unknown";
    NSMutableString *safe = [NSMutableString stringWithCapacity:trackId.length];
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < trackId.length; i++) {
        unichar c = [trackId characterAtIndex:i];
        if ([allowed characterIsMember:c] || c == '_' || c == '-') {
            [safe appendFormat:@"%C", c];
        } else {
            [safe appendFormat:@"_%02x", c];
        }
    }
    return safe;
}

- (nullable NSString *)existingFilePathForSafeKey:(NSString *)safeKey {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *mapped = nil;
    @synchronized (self.diskFileNames) {
        mapped = self.diskFileNames[safeKey];
    }
    if (mapped.length > 0) {
        NSString *p = [self.cacheDirectory stringByAppendingPathComponent:mapped];
        if ([fm fileExistsAtPath:p]) return p;
    }
    for (NSString *ext in [SPAudioCacheManager supportedAudioExtensions]) {
        NSString *name = [NSString stringWithFormat:@"%@.%@", safeKey, ext];
        NSString *p = [self.cacheDirectory stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:p]) {
            @synchronized (self.diskFileNames) {
                self.diskFileNames[safeKey] = name;
            }
            return p;
        }
    }
    return nil;
}

- (nullable NSURL *)diskFileURLIfExistsForSafeKey:(NSString *)safeKey {
    NSString *path = [self existingFilePathForSafeKey:safeKey];
    NSNumber *indexedSize = [self.diskIndexCache objectForKey:safeKey];
    if (indexedSize && path.length > 0) {
        [self persistManifestAsync];
        return [NSURL fileURLWithPath:path];
    }
    if (indexedSize) {
        [self.diskIndexCache removeObjectForKey:safeKey];
        [self persistManifestAsync];
    }
    return nil;
}

#pragma mark - Public API

- (BOOL)hasCachedTrack:(SPTrack *)track {
    if (track.identifier.length == 0) return NO;
    NSString *safeKey = [self safeKeyForTrackId:track.identifier];
    if ([self.diskIndexCache peekObjectForKey:safeKey] && [self existingFilePathForSafeKey:safeKey] != nil) {
        return YES;
    }
    AVURLAsset *memAsset = [self.assetCache peekObjectForKey:safeKey];
    if (memAsset != nil) {
        if (memAsset.URL.isFileURL || [self validCachedURLForSafeKey:safeKey peekOnly:YES] != nil) {
            return YES;
        }
    }
    return NO;
}

- (void)resolvePlayableAssetForTrack:(SPTrack *)track
                          completion:(void (^)(AVURLAsset *_Nullable, BOOL, NSError *_Nullable))completion {
    if (!completion) return;
    if (!track || track.identifier.length == 0) {
        completion(nil, NO, [NSError errorWithDomain:SPMusicErrorDomain
                                                code:SPMusicErrorNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"无效曲目"}]);
        return;
    }

    self.totalRequestCount += 1;
    NSString *safeKey = [self safeKeyForTrackId:track.identifier];

    // 1. 优先命中 L2 本地磁盘音频文件（0ms 本地秒播）
    NSURL *localURL = [self diskFileURLIfExistsForSafeKey:safeKey];
    if (localURL) {
        self.totalHitCount += 1;
        AVURLAsset *localAsset = [AVURLAsset URLAssetWithURL:localURL options:nil];
        [self.assetCache setObject:localAsset forKey:safeKey cost:1];
        completion(localAsset, YES, nil);
        return;
    }

    // 2. 命中 L1 内存预热好的 AVURLAsset（非本地文件需校验 URL 未超过 TTL）
    AVURLAsset *memAsset = [self.assetCache objectForKey:safeKey];
    if (memAsset) {
        NSURL *validRemote = [self validCachedURLForSafeKey:safeKey peekOnly:NO];
        if (memAsset.URL.isFileURL || validRemote != nil) {
            self.totalHitCount += 1;
            NSURL *remoteURL = validRemote ?: memAsset.URL;
            if (remoteURL && !remoteURL.isFileURL) {
                [self downloadToDiskInBackgroundForSafeKey:safeKey remoteURL:remoteURL];
            }
            completion(memAsset, YES, nil);
            return;
        }
        [self.assetCache removeObjectForKey:safeKey];
    }

    // 3. 命中有效 L1 URL 缓存，或向 Repository 请求真实播放地址
    NSURL *cachedRemoteURL = [self validCachedURLForSafeKey:safeKey peekOnly:NO];
    if (cachedRemoteURL) {
        self.totalHitCount += 1;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:cachedRemoteURL options:nil];
        [self.assetCache setObject:asset forKey:safeKey cost:1];
        [self downloadToDiskInBackgroundForSafeKey:safeKey remoteURL:cachedRemoteURL];
        completion(asset, YES, nil);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[SPMusicRepository shared] fetchPlayURLForTrack:track completion:^(NSURL *url, NSError *error) {
        if (!url || error) {
            completion(nil, NO, error);
            return;
        }
        [weakSelf cacheRemoteURL:url forSafeKey:safeKey];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        [weakSelf.assetCache setObject:asset forKey:safeKey cost:1];
        [weakSelf downloadToDiskInBackgroundForSafeKey:safeKey remoteURL:url];
        completion(asset, NO, nil);
    }];
}

- (void)preloadTracks:(NSArray<SPTrack *> *)tracks {
    for (SPTrack *track in tracks) {
        if (!track || track.identifier.length == 0) continue;
        NSString *safeKey = [self safeKeyForTrackId:track.identifier];

        if ([self.diskIndexCache peekObjectForKey:safeKey] && [self existingFilePathForSafeKey:safeKey] != nil) {
            continue;
        }

        NSURL *cachedURL = [self validCachedURLForSafeKey:safeKey peekOnly:YES];
        if (cachedURL) {
            [self warmupAssetAndDiskForSafeKey:safeKey remoteURL:cachedURL];
            continue;
        }

        __weak typeof(self) weakSelf = self;
        [[SPMusicRepository shared] fetchPlayURLForTrack:track completion:^(NSURL *url, NSError *error) {
            if (!url || error) return;
            [weakSelf cacheRemoteURL:url forSafeKey:safeKey];
            [weakSelf warmupAssetAndDiskForSafeKey:safeKey remoteURL:url];
        }];
    }
}

- (void)warmupAssetAndDiskForSafeKey:(NSString *)safeKey remoteURL:(NSURL *)remoteURL {
    if (![self.assetCache peekObjectForKey:safeKey]) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:remoteURL options:nil];
        [self.assetCache setObject:asset forKey:safeKey cost:1];
        [asset loadValuesAsynchronouslyForKeys:@[@"playable", @"duration"] completionHandler:nil];
    }
    [self downloadToDiskInBackgroundForSafeKey:safeKey remoteURL:remoteURL];
}

- (void)downloadToDiskInBackgroundForSafeKey:(NSString *)safeKey remoteURL:(NSURL *)remoteURL {
    if (remoteURL.isFileURL) return;
    if ([self existingFilePathForSafeKey:safeKey] != nil) return;

    NSString *ext = [self audioExtensionForRemoteURL:remoteURL];
    NSString *fileName = [NSString stringWithFormat:@"%@.%@", safeKey, ext];
    NSString *finalPath = [self.cacheDirectory stringByAppendingPathComponent:fileName];

    dispatch_async(self.ioQueue, ^{
        if (self.activeDownloads[safeKey]) return;
        if ([self existingFilePathForSafeKey:safeKey] != nil) return;

        __weak typeof(self) weakSelf = self;
        NSURLSessionDownloadTask *task = [self.downloadSession downloadTaskWithURL:remoteURL
                                                                 completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            NSHTTPURLResponse *httpResp = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            BOOL statusOK = (!httpResp || (httpResp.statusCode >= 200 && httpResp.statusCode < 300));

            if (!error && statusOK && location) {
                NSString *tmpPath = [finalPath stringByAppendingString:@".tmp"];
                NSFileManager *fm = [NSFileManager defaultManager];
                [fm removeItemAtPath:tmpPath error:nil];
                if ([fm copyItemAtURL:location toURL:[NSURL fileURLWithPath:tmpPath] error:nil]) {
                    [fm removeItemAtPath:finalPath error:nil];
                    if ([fm moveItemAtPath:tmpPath toPath:finalPath error:nil]) {
                        unsigned long long fileSize = [[fm attributesOfItemAtPath:finalPath error:nil] fileSize];
                        if (fileSize > 0) {
                            @synchronized (strongSelf.diskFileNames) {
                                strongSelf.diskFileNames[safeKey] = fileName;
                            }
                            [strongSelf.diskIndexCache setObject:@(fileSize) forKey:safeKey cost:(NSUInteger)fileSize];
                            [strongSelf persistManifestAsync];
                        }
                    } else {
                        [fm removeItemAtPath:tmpPath error:nil];
                    }
                }
            }

            dispatch_async(strongSelf.ioQueue, ^{
                [strongSelf.activeDownloads removeObjectForKey:safeKey];
            });
        }];
        task.priority = NSURLSessionTaskPriorityLow;
        self.activeDownloads[safeKey] = task;
        [task resume];
    });
}

- (void)clearMemoryCaches {
    [self.resolvedURLCache removeAllObjects];
    [self.assetCache removeAllObjects];
}

- (void)clearAllCaches {
    [self clearMemoryCaches];
    [self.diskIndexCache removeAllObjects];
    @synchronized (self.diskFileNames) {
        [self.diskFileNames removeAllObjects];
    }
    self.totalHitCount = 0;
    self.totalRequestCount = 0;

    NSString *dir = self.cacheDirectory;
    dispatch_async(self.ioQueue, ^{
        for (NSURLSessionDownloadTask *task in self.activeDownloads.allValues) {
            [task cancel];
        }
        [self.activeDownloads removeAllObjects];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:dir error:nil];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
}

@end
