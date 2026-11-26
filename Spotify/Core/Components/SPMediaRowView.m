//
//  SPMediaRowView.m
//  Spotify
//

#import "SPMediaRowView.h"
#import "SPNowPlayingIndicatorView.h"
#import "SPPlayerService.h"

@interface SPMediaRowView ()
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) SPNowPlayingIndicatorView *playingIndicator;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIStackView *textStack;
@end

@implementation SPMediaRowView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _coverSize = 56;

        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 4;
        [self addSubview:_coverView];

        _playingIndicator = [SPNowPlayingIndicatorView new];
        _playingIndicator.hidden = YES;
        [_playingIndicator setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_playingIndicator setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightRegular];
        _titleLabel.textColor = SPTheme.textPrimaryColor;

        UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[_playingIndicator, _titleLabel]];
        titleRow.axis = UILayoutConstraintAxisHorizontal;
        titleRow.alignment = UIStackViewAlignmentCenter;
        titleRow.spacing = 6;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [SPTheme monospacedDigitFontOfSize:13 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = SPTheme.textSecondaryColor;

        _textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, _subtitleLabel]];
        _textStack.axis = UILayoutConstraintAxisVertical;
        _textStack.spacing = 3;
        [self addSubview:_textStack];

        [self remakeLayout];
    }
    return self;
}

- (void)remakeLayout {
    BOOL showsCover = self.coverSize > 0;
    self.coverView.hidden = !showsCover;
    [self.coverView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self);
        make.centerY.equalTo(self);
        make.size.mas_equalTo(CGSizeMake(self.coverSize, self.coverSize));
        make.top.greaterThanOrEqualTo(self);
        make.bottom.lessThanOrEqualTo(self);
    }];
    [self.textStack mas_remakeConstraints:^(MASConstraintMaker *make) {
        if (showsCover) make.left.equalTo(self.coverView.mas_right).offset(12);
        else make.left.equalTo(self);
        make.right.equalTo(self);
        make.centerY.equalTo(self);
        make.top.greaterThanOrEqualTo(self);
        make.bottom.lessThanOrEqualTo(self);
    }];
}

- (void)setCoverSize:(CGFloat)coverSize {
    if (_coverSize == coverSize) return;
    _coverSize = coverSize;
    [self remakeLayout];
}

- (void)setActive:(BOOL)active {
    [self setActive:active isPlaying:[SPPlayerService shared].isPlaying];
}

- (void)setActive:(BOOL)active isPlaying:(BOOL)isPlaying {
    _active = active;
    self.titleLabel.textColor = active ? SPTheme.accentColor : SPTheme.textPrimaryColor;
    self.playingIndicator.hidden = !active;
    self.playingIndicator.animating = (active && isPlaying);
}

- (void)configureWithItem:(id<SPMediaItem>)item {
    self.titleLabel.text = item.title;
    self.subtitleLabel.text = item.subtitle;
    BOOL circular = item.mediaType == SPMediaTypeArtist;
    self.coverView.layer.cornerRadius = circular ? self.coverSize / 2 : 4;
    if (self.coverSize > 0) [self.coverView sp_setCoverWithItem:item];
}

@end
