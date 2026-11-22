//
//  SPHaptics.m
//  Spotify
//

#import "SPHaptics.h"

static NSString * const SPHapticsEnabledDefaultsKey = @"sp_haptics_enabled_v1";
static BOOL sHapticsInitialized = NO;
static BOOL sHapticsEnabled = YES;

@implementation SPHaptics

+ (void)ensureInitializedLocked {
    if (sHapticsInitialized) return;
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:SPHapticsEnabledDefaultsKey];
    sHapticsEnabled = saved ? saved.boolValue : YES;
    sHapticsInitialized = YES;
}

+ (BOOL)isEnabled {
    @synchronized (self) {
        [self ensureInitializedLocked];
        return sHapticsEnabled;
    }
}

+ (void)setEnabled:(BOOL)enabled {
    @synchronized (self) {
        sHapticsEnabled = enabled;
        sHapticsInitialized = YES;
    }
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:SPHapticsEnabledDefaultsKey];
}

+ (void)light {
    if (!self.isEnabled) return;
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];
}

+ (void)medium {
    if (!self.isEnabled) return;
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [gen impactOccurred];
}

+ (void)selection {
    if (!self.isEnabled) return;
    UISelectionFeedbackGenerator *gen = [UISelectionFeedbackGenerator new];
    [gen selectionChanged];
}

@end
