//
//  SPLibraryActionSheet.m
//  Spotify
//
//  Spotify
//

#import "SPLibraryActionSheet.h"
#import "SPLibraryStore.h"
#import "SPHaptics.h"
#import "SPToast.h"

@implementation SPLibraryActionSheet

+ (void)presentCreatePlaylistAlertFrom:(UIViewController *)vc
                            completion:(void (^ _Nullable)(SPPlaylist *created))completion {
    if (!vc) return;
    [SPHaptics light];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建个人歌单"
                                                                   message:@"为你的私人歌单取一个名字"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    alert.view.tintColor = SPTheme.accentColor;

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"例如：深夜微醺 / 通勤循环";
        field.returnKeyType = UIReturnKeyDone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"歌单简介（可选）";
        field.returnKeyType = UIReturnKeyDone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text ?: @"";
        NSString *desc = alert.textFields.count > 1 ? alert.textFields[1].text : nil;
        SPPlaylist *created = [[SPLibraryStore shared] createPlaylistWithName:name desc:desc];
        [SPHaptics medium];
        [SPToast showMessage:[NSString stringWithFormat:@"已创建歌单「%@」", created.name]];
        if (completion) completion(created);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)presentAddTrack:(SPTrack *)track toPlaylistFrom:(UIViewController *)vc {
    if (!vc || !track) return;
    [SPHaptics light];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"添加到歌单"
                                                                   message:[NSString stringWithFormat:@"%@ · %@", track.name ?: @"", [track artistNames]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = SPTheme.interfaceStyle;
    sheet.view.tintColor = SPTheme.accentColor;

    SPLibraryStore *store = [SPLibraryStore shared];
    BOOL liked = [store isTrackLiked:track.identifier];
    NSString *likedTitle = [NSString stringWithFormat:@"已点赞的歌曲%@（%lu 首）",
                            liked ? @" ✓" : @"",
                            (unsigned long)store.likedTracks.count];
    [sheet addAction:[UIAlertAction actionWithTitle:likedTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        if ([store addTrack:track toPlaylistId:SPLikedSongsPlaylistId]) {
            [SPHaptics medium];
            [SPToast showMessage:@"已添加到「已点赞的歌曲」"];
        } else {
            [SPToast showMessage:@"该歌曲已在「已点赞的歌曲」中"];
        }
    }]];

    for (SPPlaylist *pl in store.userPlaylists) {
        NSString *title = [NSString stringWithFormat:@"%@（%lu 首）", pl.name, (unsigned long)pl.tracks.count];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            if ([store addTrack:track toPlaylistId:pl.identifier]) {
                [SPHaptics medium];
                [SPToast showMessage:[NSString stringWithFormat:@"已添加到「%@」", pl.name]];
            } else {
                [SPToast showMessage:[NSString stringWithFormat:@"歌曲已在「%@」中", pl.name]];
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"＋ 新建歌单并添加"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self presentCreatePlaylistAlertFrom:vc completion:^(SPPlaylist *created) {
            [[SPLibraryStore shared] addTrack:track toPlaylistId:created.identifier];
            [SPToast showMessage:[NSString stringWithFormat:@"已加入新歌单「%@」", created.name]];
        }];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [SPTheme configurePopoverForViewController:sheet sourceView:nil presentingVC:vc];
    [vc presentViewController:sheet animated:YES completion:nil];
}

@end
