//
//  SPListeningStatsStore.m
//  Spotify
//

#import "SPListeningStatsStore.h"
#import "SPAuthService.h"
#import <QuartzCore/QuartzCore.h>
#import <YYModel/YYModel.h>

NSNotificationName const SPListeningStatsDidUpdateNotification = @"com.dyyxs.spotify.listeningStatsUpdated";
static NSString * const SPListeningStatsDefaultsKeyPrefix = @"com.dyyxs.spotify.listeningStats.v2.";

@implementation SPListeningChartPoint
@end

@implementation SPListeningTopTrackItem
@end

@implementation SPListeningTopArtistItem
@end

@implementation SPListeningStatsSnapshot
@end

@interface SPListeningStatsStore () <SPAuthObserver>
@property (nonatomic, copy) NSString *activeScopeKey;
/// dateKey ("yyyy-MM-dd") -> @{ @"sec": @(double), @"plays": @(NSUInteger) }
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *dailyBuckets;
/// 24 小时分桶 ("0".."23") -> @{ @"sec": @(double), @"plays": @(NSUInteger) }
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *hourlyBuckets;
/// trackId -> @{ @"track": jsonDict, @"plays": @(NSUInteger), @"sec": @(double) }
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *trackBuckets;
/// artistKey -> @{ @"artist": jsonDict, @"plays": @(NSUInteger), @"sec": @(double) }
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *artistBuckets;

@property (nonatomic, assign) CFTimeInterval lastTickMediaTime;
@property (nonatomic, assign) CFTimeInterval lastPersistMediaTime;
@property (nonatomic, copy, nullable) NSString *lastTickTrackId;
@property (nonatomic, copy, nullable) NSString *lastRecordTrackId;
@property (nonatomic, assign) CFTimeInterval lastRecordMediaTime;
@property (nonatomic, assign) NSUInteger lastRecordedSessionId;
@end

@implementation SPListeningStatsStore

+ (instancetype)shared {
    static SPListeningStatsStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [SPListeningStatsStore new];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _dailyBuckets = [NSMutableDictionary dictionary];
        _hourlyBuckets = [NSMutableDictionary dictionary];
        _trackBuckets = [NSMutableDictionary dictionary];
        _artistBuckets = [NSMutableDictionary dictionary];
        _activeScopeKey = [self currentScopeKey];
        [self loadFromDefaultsLocked];
        [[SPAuthService shared] addObserver:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleAppWillResignActive)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - User Scope & Persistence

- (NSString *)currentScopeKey {
    SPUser *user = [SPAuthService shared].currentUser;
    return user.userId.length > 0 ? user.userId : (user.account.length > 0 ? user.account.lowercaseString : @"guest");
}

- (NSString *)scopedDefaultsKey {
    return [SPListeningStatsDefaultsKeyPrefix stringByAppendingString:(self.activeScopeKey.length ? self.activeScopeKey : @"guest")];
}

- (void)ensureScopeMatchesCurrentUserLocked {
    NSString *expected = [self currentScopeKey];
    if (![self.activeScopeKey isEqualToString:expected]) {
        self.activeScopeKey = expected;
        self.lastTickMediaTime = 0;
        self.lastTickTrackId = nil;
        self.lastRecordedSessionId = 0;
        self.lastRecordTrackId = nil;
        self.lastRecordMediaTime = 0;
        [self loadFromDefaultsLocked];
    }
}

- (void)reloadForCurrentUser {
    @synchronized (self) {
        self.activeScopeKey = [self currentScopeKey];
        self.lastTickMediaTime = 0;
        self.lastTickTrackId = nil;
        self.lastRecordedSessionId = 0;
        self.lastRecordTrackId = nil;
        self.lastRecordMediaTime = 0;
        [self loadFromDefaultsLocked];
    }
    [self postUpdateNotification];
}

- (void)authServiceDidChangeUser:(SPAuthService *)authService {
    @synchronized (self) {
        if ([self.activeScopeKey isEqualToString:[self currentScopeKey]]) {
            return;
        }
    }
    [self reloadForCurrentUser];
}

- (void)handleAppWillResignActive {
    @synchronized (self) {
        self.lastTickMediaTime = 0;
        [self saveToDefaultsLocked];
    }
}

- (void)clearCurrentUserStats {
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        [self.dailyBuckets removeAllObjects];
        [self.hourlyBuckets removeAllObjects];
        [self.trackBuckets removeAllObjects];
        [self.artistBuckets removeAllObjects];
        self.lastTickMediaTime = 0;
        self.lastTickTrackId = nil;
        self.lastRecordedSessionId = 0;
        self.lastRecordTrackId = nil;
        self.lastRecordMediaTime = 0;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self scopedDefaultsKey]];
    }
    [self postUpdateNotification];
}

- (void)postUpdateNotification {
    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPListeningStatsDidUpdateNotification object:self];
    };
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

+ (NSString *)formatDate:(NSDate *)date withFormatter:(NSDateFormatter *)formatter {
    if (!date || !formatter) return @"";
    @synchronized (formatter) {
        formatter.timeZone = NSTimeZone.localTimeZone;
        return [formatter stringFromDate:date];
    }
}

+ (NSDateFormatter *)dayKeyFormatter {
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        fmt.dateFormat = @"yyyy-MM-dd";
    });
    return fmt;
}

+ (NSDateFormatter *)monthDayFormatter {
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        fmt.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        fmt.dateFormat = @"M/d";
    });
    return fmt;
}

+ (NSDateFormatter *)fullDateFormatter {
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        fmt.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        fmt.dateFormat = @"M月d日";
    });
    return fmt;
}

- (void)loadFromDefaultsLocked {
    [self.dailyBuckets removeAllObjects];
    [self.hourlyBuckets removeAllObjects];
    [self.trackBuckets removeAllObjects];
    [self.artistBuckets removeAllObjects];

    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:[self scopedDefaultsKey]];
    if (data) {
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([root isKindOfClass:NSDictionary.class]) {
            NSDictionary *daily = root[@"daily"];
            if ([daily isKindOfClass:NSDictionary.class]) {
                [daily enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSDictionary.class]) {
                        self.dailyBuckets[key] = [obj mutableCopy];
                    }
                }];
            }
            NSDictionary *hourly = root[@"hourly"];
            if ([hourly isKindOfClass:NSDictionary.class]) {
                [hourly enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSDictionary.class]) {
                        self.hourlyBuckets[key] = [obj mutableCopy];
                    }
                }];
            }
            NSDictionary *tracks = root[@"tracks"];
            if ([tracks isKindOfClass:NSDictionary.class]) {
                [tracks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSDictionary.class]) {
                        self.trackBuckets[key] = [obj mutableCopy];
                    }
                }];
            }
            NSDictionary *artists = root[@"artists"];
            if ([artists isKindOfClass:NSDictionary.class]) {
                [artists enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSDictionary.class]) {
                        self.artistBuckets[key] = [obj mutableCopy];
                    }
                }];
            }
        }
    }
}

- (void)saveToDefaultsLocked {
    // 清理超过 45 天的旧日期桶，保持轻量高速
    if (self.dailyBuckets.count > 45) {
        NSArray<NSString *> *sortedKeys = [self.dailyBuckets.allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger excess = sortedKeys.count - 45;
        for (NSUInteger i = 0; i < excess; i++) {
            [self.dailyBuckets removeObjectForKey:sortedKeys[i]];
        }
    }
    NSDictionary *payload = @{
        @"daily": self.dailyBuckets ?: @{},
        @"hourly": self.hourlyBuckets ?: @{},
        @"tracks": self.trackBuckets ?: @{},
        @"artists": self.artistBuckets ?: @{},
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:[self scopedDefaultsKey]];
    }
}

#pragma mark - Recording

- (void)applySecondsLocked:(NSTimeInterval)seconds
                  forTrack:(nullable SPTrack *)track
                    atDate:(NSDate *)date
                 countPlay:(BOOL)countPlay {
    NSDate *safeDate = date ?: [NSDate date];
    NSString *dayKey = [SPListeningStatsStore formatDate:safeDate withFormatter:[SPListeningStatsStore dayKeyFormatter]];
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSInteger hour = [cal component:NSCalendarUnitHour fromDate:safeDate];
    NSString *hourKey = [NSString stringWithFormat:@"%ld", (long)hour];

    NSMutableDictionary *dayEntry = self.dailyBuckets[dayKey];
    if (!dayEntry) {
        dayEntry = [NSMutableDictionary dictionaryWithDictionary:@{@"sec": @0.0, @"plays": @0}];
        self.dailyBuckets[dayKey] = dayEntry;
    }
    if (seconds > 0) {
        dayEntry[@"sec"] = @([dayEntry[@"sec"] doubleValue] + seconds);
    }
    if (countPlay) {
        dayEntry[@"plays"] = @([dayEntry[@"plays"] unsignedIntegerValue] + 1);
    }

    NSMutableDictionary *hourEntry = self.hourlyBuckets[hourKey];
    if (!hourEntry) {
        hourEntry = [NSMutableDictionary dictionaryWithDictionary:@{@"sec": @0.0, @"plays": @0}];
        self.hourlyBuckets[hourKey] = hourEntry;
    }
    if (seconds > 0) {
        hourEntry[@"sec"] = @([hourEntry[@"sec"] doubleValue] + seconds);
    }
    if (countPlay) {
        hourEntry[@"plays"] = @([hourEntry[@"plays"] unsignedIntegerValue] + 1);
    }

    if (track && track.identifier.length > 0) {
        NSMutableDictionary *tEntry = self.trackBuckets[track.identifier];
        if (!tEntry) {
            id trackJSON = [track yy_modelToJSONObject];
            tEntry = [NSMutableDictionary dictionaryWithDictionary:@{
                @"track": [trackJSON isKindOfClass:NSDictionary.class] ? trackJSON : @{},
                @"plays": @0,
                @"sec": @0.0,
            }];
            self.trackBuckets[track.identifier] = tEntry;
        }
        if (seconds > 0) {
            tEntry[@"sec"] = @([tEntry[@"sec"] doubleValue] + seconds);
        }
        if (countPlay) {
            tEntry[@"plays"] = @([tEntry[@"plays"] unsignedIntegerValue] + 1);
        }

        SPArtist *primaryArtist = track.artists.firstObject;
        NSString *artistKey = primaryArtist.identifier.length > 0 ? primaryArtist.identifier : primaryArtist.name;
        NSString *effectiveCover = primaryArtist.coverURL.length > 0
            ? primaryArtist.coverURL
            : (track.coverURL.length > 0 ? track.coverURL : nil);
        if (artistKey.length > 0 && primaryArtist) {
            NSMutableDictionary *aEntry = self.artistBuckets[artistKey];
            if (!aEntry) {
                id artistJSON = [primaryArtist yy_modelToJSONObject];
                NSMutableDictionary *mutableArtist = [artistJSON isKindOfClass:NSDictionary.class]
                    ? [artistJSON mutableCopy]
                    : [NSMutableDictionary dictionary];
                if ([mutableArtist[@"coverURL"] length] == 0 && effectiveCover.length > 0) {
                    mutableArtist[@"coverURL"] = effectiveCover;
                }
                aEntry = [NSMutableDictionary dictionaryWithDictionary:@{
                    @"artist": mutableArtist,
                    @"plays": @0,
                    @"sec": @0.0,
                }];
                self.artistBuckets[artistKey] = aEntry;
            } else {
                NSDictionary *oldJSON = aEntry[@"artist"];
                if (primaryArtist.coverURL.length > 0 &&
                    (![oldJSON isKindOfClass:NSDictionary.class] || ![oldJSON[@"coverURL"] isEqualToString:primaryArtist.coverURL])) {
                    id artistJSON = [primaryArtist yy_modelToJSONObject];
                    if ([artistJSON isKindOfClass:NSDictionary.class]) {
                        aEntry[@"artist"] = artistJSON;
                    }
                } else if ([oldJSON isKindOfClass:NSDictionary.class] && [oldJSON[@"coverURL"] length] == 0 && effectiveCover.length > 0) {
                    NSMutableDictionary *patched = [oldJSON mutableCopy];
                    patched[@"coverURL"] = effectiveCover;
                    aEntry[@"artist"] = patched;
                }
            }
            if (seconds > 0) {
                aEntry[@"sec"] = @([aEntry[@"sec"] doubleValue] + seconds);
            }
            if (countPlay) {
                aEntry[@"plays"] = @([aEntry[@"plays"] unsignedIntegerValue] + 1);
            }
        }
    }
}

- (void)recordTrackPlay:(SPTrack *)track {
    [self recordTrackPlay:track sessionId:0];
}

- (void)recordTrackPlay:(SPTrack *)track sessionId:(NSUInteger)sessionId {
    if (!track || track.identifier.length == 0) return;
    CFTimeInterval now = CACurrentMediaTime();
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        if (sessionId > 0 && sessionId == self.lastRecordedSessionId) {
            return;
        }
        BOOL rapidDuplicate = (sessionId == 0)
            && [self.lastRecordTrackId isEqualToString:track.identifier]
            && (now - self.lastRecordMediaTime) < 4.0;
        if (rapidDuplicate) {
            self.lastTickTrackId = track.identifier;
            self.lastTickMediaTime = now;
            return;
        }
        if (sessionId > 0) {
            self.lastRecordedSessionId = sessionId;
        }
        self.lastRecordTrackId = track.identifier;
        self.lastRecordMediaTime = now;
        self.lastTickTrackId = track.identifier;
        self.lastTickMediaTime = now;
        // 每次有效起播仅记 1 次播放，聆听时长严格由真实播放进度累加，不预支虚假时长
        [self applySecondsLocked:0.0 forTrack:track atDate:[NSDate date] countPlay:YES];
        [self saveToDefaultsLocked];
    }
    [self postUpdateNotification];
}

- (void)recordPlaybackProgressForTrack:(SPTrack *)track isPlaying:(BOOL)isPlaying {
    BOOL shouldNotify = NO;
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        if (!isPlaying || !track || track.identifier.length == 0) {
            if (self.lastTickMediaTime > 0) {
                self.lastTickMediaTime = 0;
                [self saveToDefaultsLocked];
            }
            return;
        }
        CFTimeInterval now = CACurrentMediaTime();
        if (![self.lastTickTrackId isEqualToString:track.identifier] || self.lastTickMediaTime <= 0) {
            self.lastTickTrackId = track.identifier;
            self.lastTickMediaTime = now;
            return;
        }
        CFTimeInterval delta = now - self.lastTickMediaTime;
        self.lastTickMediaTime = now;
        if (delta <= 0.05 || delta > 3.5) {
            return;
        }
        [self applySecondsLocked:delta forTrack:track atDate:[NSDate date] countPlay:NO];
        if (now - self.lastPersistMediaTime >= 8.0) {
            self.lastPersistMediaTime = now;
            [self saveToDefaultsLocked];
            shouldNotify = YES;
        }
    }
    if (shouldNotify) {
        [self postUpdateNotification];
    }
}

- (void)recordListeningSeconds:(NSTimeInterval)seconds
                      forTrack:(SPTrack *)track
                        atDate:(NSDate *)date
                     countPlay:(BOOL)countPlay {
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        [self applySecondsLocked:MAX(0.0, seconds) forTrack:track atDate:(date ?: [NSDate date]) countPlay:countPlay];
        [self saveToDefaultsLocked];
    }
    [self postUpdateNotification];
}

#pragma mark - Snapshot Construction

+ (NSString *)weekdayShortNameForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSInteger wd = [cal component:NSCalendarUnitWeekday fromDate:date];
    NSArray<NSString *> *names = @[@"周日", @"周一", @"周二", @"周三", @"周四", @"周五", @"周六"];
    NSInteger idx = MAX(0, MIN((NSInteger)names.count - 1, wd - 1));
    return names[idx];
}

- (SPListeningStatsSnapshot *)currentSnapshot {
    @synchronized (self) {
        [self ensureScopeMatchesCurrentUserLocked];
        return [self buildSnapshotFromDaily:self.dailyBuckets
                                     hourly:self.hourlyBuckets
                                     tracks:self.trackBuckets
                                    artists:self.artistBuckets];
    }
}

- (SPListeningStatsSnapshot *)buildSnapshotFromDaily:(NSDictionary<NSString *, NSDictionary *> *)daily
                                              hourly:(NSDictionary<NSString *, NSDictionary *> *)hourly
                                              tracks:(NSDictionary<NSString *, NSDictionary *> *)tracks
                                             artists:(NSDictionary<NSString *, NSDictionary *> *)artists {
    SPListeningStatsSnapshot *snap = [SPListeningStatsSnapshot new];

    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];

    // 1. 近 7 日与近 14 日曲线
    NSMutableArray<SPListeningChartPoint *> *pts7 = [NSMutableArray arrayWithCapacity:7];
    NSMutableArray<SPListeningChartPoint *> *pts14 = [NSMutableArray arrayWithCapacity:14];
    for (NSInteger offset = 13; offset >= 0; offset--) {
        NSDate *day = [cal dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0];
        NSString *key = [SPListeningStatsStore formatDate:day withFormatter:[SPListeningStatsStore dayKeyFormatter]];
        NSDictionary *bucket = daily[key];
        double sec = [bucket[@"sec"] doubleValue];
        NSUInteger plays = [bucket[@"plays"] unsignedIntegerValue];
        CGFloat mins = (CGFloat)(sec / 60.0);

        NSString *dateText = [SPListeningStatsStore formatDate:day withFormatter:[SPListeningStatsStore fullDateFormatter]];
        NSString *wdName = [SPListeningStatsStore weekdayShortNameForDate:day];

        SPListeningChartPoint *p14 = [SPListeningChartPoint new];
        p14.axisLabel = (offset == 0) ? @"今天" : ((offset % 3 == 0) ? [SPListeningStatsStore formatDate:day withFormatter:[SPListeningStatsStore monthDayFormatter]] : @"");
        p14.detailTitle = (offset == 0) ? [NSString stringWithFormat:@"%@ · 今天", dateText] : [NSString stringWithFormat:@"%@ · %@", dateText, wdName];
        p14.minutes = mins;
        p14.playCount = plays;
        p14.isDefaultFocus = (offset == 0);
        [pts14 addObject:p14];

        if (offset < 7) {
            SPListeningChartPoint *p7 = [SPListeningChartPoint new];
            p7.axisLabel = (offset == 0) ? @"今天" : wdName;
            p7.detailTitle = p14.detailTitle;
            p7.minutes = mins;
            p7.playCount = plays;
            p7.isDefaultFocus = (offset == 0);
            [pts7 addObject:p7];
        }
    }
    snap.points7Days = pts7;
    snap.points14Days = pts14;

    // 2. 24 小时逐时分布 + 双小时聚合曲线 (12 个节点: 00, 02, ..., 22) + 四大时段占比
    NSMutableArray<NSNumber *> *hourMins = [NSMutableArray arrayWithCapacity:24];
    NSMutableArray<NSNumber *> *hourPlays = [NSMutableArray arrayWithCapacity:24];
    NSInteger bestHour = -1;
    double bestHourSec = -1.0;
    NSUInteger bestHourPlays = 0;

    double morningSec = 0, afternoonSec = 0, eveningSec = 0, nightSec = 0;
    NSUInteger morningPlays = 0, afternoonPlays = 0, eveningPlays = 0, nightPlays = 0;
    for (NSInteger h = 0; h < 24; h++) {
        NSDictionary *hb = hourly[[NSString stringWithFormat:@"%ld", (long)h]];
        double sec = [hb[@"sec"] doubleValue];
        NSUInteger plays = [hb[@"plays"] unsignedIntegerValue];
        [hourMins addObject:@(sec / 60.0)];
        [hourPlays addObject:@(plays)];

        if (sec > bestHourSec + 0.01 || (fabs(sec - bestHourSec) <= 0.01 && plays > bestHourPlays)) {
            bestHourSec = sec;
            bestHourPlays = plays;
            bestHour = h;
        }

        if (h >= 5 && h < 11) {
            morningSec += sec;
            morningPlays += plays;
        } else if (h >= 11 && h < 17) {
            afternoonSec += sec;
            afternoonPlays += plays;
        } else if (h >= 17 && h < 22) {
            eveningSec += sec;
            eveningPlays += plays;
        } else {
            nightSec += sec;
            nightPlays += plays;
        }
    }
    snap.hourlyMinutes24 = hourMins;
    snap.hourlyPlays24 = hourPlays;
    snap.peakHour = (bestHourSec > 0.01 || bestHourPlays > 0) ? bestHour : -1;

    NSMutableArray<SPListeningChartPoint *> *ptsHourly = [NSMutableArray arrayWithCapacity:12];
    NSInteger currentHour = [cal component:NSCalendarUnitHour fromDate:[NSDate date]];
    NSInteger currentSlot = currentHour / 2;
    NSInteger peakSlot = currentSlot;
    NSInteger peakPlaySlot = currentSlot;
    CGFloat maxSlotMins = -1.0;
    NSUInteger maxSlotPlays = 0;

    for (NSInteger slot = 0; slot < 12; slot++) {
        NSInteger h0 = slot * 2;
        NSInteger h1 = h0 + 1;
        NSDictionary *b0 = hourly[[NSString stringWithFormat:@"%ld", (long)h0]];
        NSDictionary *b1 = hourly[[NSString stringWithFormat:@"%ld", (long)h1]];
        double sec = [b0[@"sec"] doubleValue] + [b1[@"sec"] doubleValue];
        NSUInteger plays = [b0[@"plays"] unsignedIntegerValue] + [b1[@"plays"] unsignedIntegerValue];
        CGFloat mins = (CGFloat)(sec / 60.0);
        if (mins > maxSlotMins) {
            maxSlotMins = mins;
            peakSlot = slot;
        }
        if (plays > maxSlotPlays) {
            maxSlotPlays = plays;
            peakPlaySlot = slot;
        }
        NSString *periodTag = (h0 >= 5 && h0 < 11) ? @"清晨" : ((h0 >= 11 && h0 < 17) ? @"午后" : ((h0 >= 17 && h0 < 22) ? @"傍晚" : @"深夜"));
        SPListeningChartPoint *ph = [SPListeningChartPoint new];
        ph.axisLabel = (slot % 2 == 0) ? [NSString stringWithFormat:@"%02ldh", (long)h0] : @"";
        ph.detailTitle = [NSString stringWithFormat:@"%02ld:00 - %02ld:59 · %@", (long)h0, (long)h1, periodTag];
        ph.minutes = mins;
        ph.playCount = plays;
        [ptsHourly addObject:ph];
    }
    NSInteger focusSlot = currentSlot;
    if (maxSlotMins > 0.01) {
        focusSlot = peakSlot;
    } else if (maxSlotPlays > 0) {
        focusSlot = peakPlaySlot;
    }
    ptsHourly[focusSlot].isDefaultFocus = YES;
    snap.pointsHourly = ptsHourly;

    // 3. 汇总指标与诚实时段分布描述
    __block double totalSec = 0;
    __block NSUInteger totalPlays = 0;
    __block NSUInteger activeDays = 0;
    [daily enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
        double s = [obj[@"sec"] doubleValue];
        NSUInteger p = [obj[@"plays"] unsignedIntegerValue];
        totalSec += s;
        totalPlays += p;
        if (p > 0 || s >= 1.0) activeDays += 1;
    }];
    snap.totalMinutes = (CGFloat)(totalSec / 60.0);
    snap.totalPlayCount = totalPlays;
    snap.activeDaysCount = activeDays;

    double periodSecSum = morningSec + afternoonSec + eveningSec + nightSec;
    NSUInteger periodPlaySum = morningPlays + afternoonPlays + eveningPlays + nightPlays;
    if ((totalPlays == 0 && totalSec <= 0.01) || (periodSecSum <= 0.01 && periodPlaySum == 0)) {
        snap.periodShares = @[@0.0, @0.0, @0.0, @0.0];
        snap.dominantPeriodIndex = -1;
        snap.personaTitle = @"暂无记录";
        snap.personaSummary = @"播放任意歌曲后，这里会自动记录你的真实聆听时长与偏爱时段。";
    } else {
        BOOL useSeconds = (periodSecSum > 0.01);
        double vals[4] = {
            useSeconds ? morningSec : (double)morningPlays,
            useSeconds ? afternoonSec : (double)afternoonPlays,
            useSeconds ? eveningSec : (double)eveningPlays,
            useSeconds ? nightSec : (double)nightPlays,
        };
        double denom = vals[0] + vals[1] + vals[2] + vals[3];
        if (denom <= 0.0001) denom = 1.0;

        snap.periodShares = @[
            @(vals[0] / denom),
            @(vals[1] / denom),
            @(vals[2] / denom),
            @(vals[3] / denom),
        ];
        NSUInteger maxIdx = 0;
        double maxVal = -1.0;
        for (NSUInteger i = 0; i < 4; i++) {
            if (vals[i] > maxVal) {
                maxVal = vals[i];
                maxIdx = i;
            }
        }
        snap.dominantPeriodIndex = (NSInteger)maxIdx;
        NSArray<NSString *> *periodTitles = @[@"清晨偏多", @"午后偏多", @"傍晚偏多", @"深夜偏多"];
        NSArray<NSString *> *periodNames = @[@"清晨", @"午后", @"傍晚", @"深夜"];
        NSInteger topPct = (NSInteger)llround((vals[maxIdx] / denom) * 100.0);
        NSInteger displayPeakHour = (snap.peakHour >= 0) ? snap.peakHour : currentHour;
        snap.personaTitle = periodTitles[maxIdx];
        snap.personaSummary = [NSString stringWithFormat:@"%ld%% 的聆听集中在%@ · %02ld:00 前后最活跃",
                               (long)topPct, periodNames[maxIdx], (long)displayPeakHour];
    }

    // 4. 常听单曲 Top 5
    NSMutableArray<SPListeningTopTrackItem *> *parsedTracks = [NSMutableArray array];
    [tracks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
        NSDictionary *json = obj[@"track"];
        SPTrack *track = [json isKindOfClass:NSDictionary.class] ? [SPTrack yy_modelWithJSON:json] : nil;
        if (!track || track.identifier.length == 0) return;
        SPListeningTopTrackItem *item = [SPListeningTopTrackItem new];
        item.track = track;
        item.playCount = [obj[@"plays"] unsignedIntegerValue];
        item.totalSeconds = [obj[@"sec"] doubleValue];
        [parsedTracks addObject:item];
    }];
    [parsedTracks sortUsingComparator:^NSComparisonResult(SPListeningTopTrackItem *a, SPListeningTopTrackItem *b) {
        if (a.playCount != b.playCount) return a.playCount > b.playCount ? NSOrderedAscending : NSOrderedDescending;
        return a.totalSeconds > b.totalSeconds ? NSOrderedAscending : NSOrderedDescending;
    }];
    snap.topTracks = parsedTracks.count > 5 ? [parsedTracks subarrayWithRange:NSMakeRange(0, 5)] : parsedTracks;

    // 5. 常听艺人 Top 6
    NSMutableArray<SPListeningTopArtistItem *> *parsedArtists = [NSMutableArray array];
    [artists enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
        NSDictionary *json = obj[@"artist"];
        SPArtist *artist = [json isKindOfClass:NSDictionary.class] ? [SPArtist yy_modelWithJSON:json] : nil;
        if (!artist || artist.name.length == 0) return;
        if (artist.coverURL.length == 0) {
            for (SPListeningTopTrackItem *ti in parsedTracks) {
                SPArtist *ta = ti.track.artists.firstObject;
                BOOL sameArtist = (artist.identifier.length > 0 && [ta.identifier isEqualToString:artist.identifier])
                    || [ta.name isEqualToString:artist.name];
                if (sameArtist && ti.track.coverURL.length > 0) {
                    artist.coverURL = ti.track.coverURL;
                    break;
                }
            }
        }
        SPListeningTopArtistItem *item = [SPListeningTopArtistItem new];
        item.artist = artist;
        item.playCount = [obj[@"plays"] unsignedIntegerValue];
        item.totalSeconds = [obj[@"sec"] doubleValue];
        [parsedArtists addObject:item];
    }];
    [parsedArtists sortUsingComparator:^NSComparisonResult(SPListeningTopArtistItem *a, SPListeningTopArtistItem *b) {
        if (a.totalSeconds != b.totalSeconds) return a.totalSeconds > b.totalSeconds ? NSOrderedAscending : NSOrderedDescending;
        return a.playCount > b.playCount ? NSOrderedAscending : NSOrderedDescending;
    }];
    snap.topArtists = parsedArtists.count > 6 ? [parsedArtists subarrayWithRange:NSMakeRange(0, 6)] : parsedArtists;

    return snap;
}

@end
