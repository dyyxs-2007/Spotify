//
//  SPLyricModel.m
//  Spotify
//

#import "SPLyricModel.h"

@implementation SPLyricLine
@end

@interface SPLyricDocument ()
@property (nonatomic, assign, readwrite) BOOL hasTranslation;
@end

@implementation SPLyricDocument

+ (NSArray<NSDictionary *> *)parsedTimedEntriesFromLRC:(nullable NSString *)rawLRC {
    if (rawLRC.length == 0) return @[];

    static NSRegularExpression *timeRegex;
    static NSRegularExpression *offsetRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timeRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
                                                             options:0
                                                               error:nil];
        offsetRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[offset:([+-]?\\d+)\\]"
                                                               options:NSRegularExpressionCaseInsensitive
                                                                 error:nil];
    });

    NSTimeInterval globalOffset = 0;
    NSTextCheckingResult *offsetMatch = [offsetRegex firstMatchInString:rawLRC options:0 range:NSMakeRange(0, rawLRC.length)];
    if (offsetMatch && offsetMatch.numberOfRanges > 1) {
        NSString *val = [rawLRC substringWithRange:[offsetMatch rangeAtIndex:1]];
        globalOffset = [val doubleValue] / 1000.0;
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSArray<NSString *> *rawLines = [rawLRC componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *rawLine in rawLines) {
        NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0) continue;

        NSArray<NSTextCheckingResult *> *matches = [timeRegex matchesInString:trimmed
                                                                      options:0
                                                                        range:NSMakeRange(0, trimmed.length)];
        if (matches.count == 0) continue;

        NSString *lyricBody = [timeRegex stringByReplacingMatchesInString:trimmed
                                                                  options:0
                                                                    range:NSMakeRange(0, trimmed.length)
                                                             withTemplate:@""];
        lyricBody = [lyricBody stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (lyricBody.length == 0) continue;

        for (NSTextCheckingResult *m in matches) {
            NSInteger mins = [[trimmed substringWithRange:[m rangeAtIndex:1]] integerValue];
            NSInteger secs = [[trimmed substringWithRange:[m rangeAtIndex:2]] integerValue];
            NSTimeInterval frac = 0;
            NSRange fracRange = [m rangeAtIndex:3];
            if (fracRange.location != NSNotFound && fracRange.length > 0) {
                NSString *fracStr = [trimmed substringWithRange:fracRange];
                double rawFrac = [fracStr doubleValue];
                if (fracStr.length == 1) frac = rawFrac * 0.1;
                else if (fracStr.length == 2) frac = rawFrac * 0.01;
                else frac = rawFrac * 0.001;
            }
            NSTimeInterval t = MAX(0.0, mins * 60.0 + secs + frac - globalOffset);
            [entries addObject:@{ @"time": @(t), @"text": lyricBody }];
        }
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSTimeInterval ta = [a[@"time"] doubleValue];
        NSTimeInterval tb = [b[@"time"] doubleValue];
        if (ta < tb) return NSOrderedAscending;
        if (ta > tb) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return entries;
}

+ (instancetype)parseLRC:(nullable NSString *)lrcText translationLRC:(nullable NSString *)tlyricText {
    SPLyricDocument *doc = [SPLyricDocument new];
    NSArray<NSDictionary *> *primaryEntries = [self parsedTimedEntriesFromLRC:lrcText];

    if (primaryEntries.count > 0) {
        doc.isSynced = YES;
        NSArray<NSDictionary *> *transEntries = [self parsedTimedEntriesFromLRC:tlyricText];

        NSMutableArray<SPLyricLine *> *lines = [NSMutableArray arrayWithCapacity:primaryEntries.count];
        NSUInteger transCursor = 0;
        BOOL anyTranslation = NO;
        BOOL instrumentalOnly = (primaryEntries.count == 1 && [primaryEntries.firstObject[@"text"] containsString:@"纯音乐"]);

        for (NSDictionary *entry in primaryEntries) {
            SPLyricLine *line = [SPLyricLine new];
            line.time = [entry[@"time"] doubleValue];
            line.text = entry[@"text"];

            if (transEntries.count > 0) {
                while (transCursor < transEntries.count &&
                       [transEntries[transCursor][@"time"] doubleValue] < line.time - 0.35) {
                    transCursor += 1;
                }
                if (transCursor < transEntries.count) {
                    NSTimeInterval dt = fabs([transEntries[transCursor][@"time"] doubleValue] - line.time);
                    if (dt <= 0.35) {
                        NSString *transText = transEntries[transCursor][@"text"];
                        if (transText.length > 0 && ![transText isEqualToString:line.text]) {
                            line.translation = transText;
                            anyTranslation = YES;
                        }
                        transCursor += 1;
                    }
                }
            }
            [lines addObject:line];
        }

        doc.lines = lines;
        doc.hasTranslation = anyTranslation;
        doc.isInstrumental = instrumentalOnly;
        return doc;
    }

    // 非逐句时间轴纯文本歌词或纯音乐提示
    NSString *cleanRaw = [lrcText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (cleanRaw.length == 0) {
        doc.lines = @[];
        doc.isSynced = NO;
        doc.isInstrumental = NO;
        return doc;
    }

    if ([cleanRaw containsString:@"纯音乐，请欣赏"] || [cleanRaw isEqualToString:@"纯音乐"]) {
        doc.lines = @[];
        doc.isSynced = NO;
        doc.isInstrumental = YES;
        return doc;
    }

    NSMutableArray<SPLyricLine *> *plainLines = [NSMutableArray array];
    NSArray<NSString *> *splits = [cleanRaw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *s in splits) {
        NSString *trimmed = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0) continue;
        SPLyricLine *line = [SPLyricLine new];
        line.time = 0;
        line.text = trimmed;
        [plainLines addObject:line];
    }
    doc.lines = plainLines;
    doc.isSynced = NO;
    return doc;
}

- (NSInteger)activeLineIndexForTime:(NSTimeInterval)time {
    if (!self.isSynced || self.lines.count == 0) return -1;
    NSTimeInterval target = time + 0.15;
    for (NSInteger i = (NSInteger)self.lines.count - 1; i >= 0; i--) {
        if (self.lines[i].time <= target) {
            return i;
        }
    }
    return -1;
}

@end
