//
//  SPHomeShortcutCell.m
//  Spotify
//

#import "SPHomeShortcutCell.h"

@interface SPHomeShortcutCell ()
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation SPHomeShortcutCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = SPTheme.highlightColor;
        self.contentView.layer.cornerRadius = 6;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.contentView.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        self.contentView.clipsToBounds = YES;

        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        [self.contentView addSubview:_coverView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightBold];
        _titleLabel.textColor = SPTheme.textPrimaryColor;
        _titleLabel.numberOfLines = 2;
        [self.contentView addSubview:_titleLabel];

        [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.top.bottom.equalTo(self.contentView);
            make.width.equalTo(self.coverView.mas_height);
        }];
        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.coverView.mas_right).offset(8);
            make.right.equalTo(self.contentView).offset(-8);
            make.centerY.equalTo(self.contentView);
        }];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.contentView.layer.borderColor = [SPTheme.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    }
}

- (void)configureWithItem:(id<SPMediaItem>)item {
    self.titleLabel.text = item.title;
    [self.coverView sp_setCoverWithItem:item];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.contentView.backgroundColor = highlighted ? SPTheme.pressedColor : SPTheme.highlightColor;
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.98, 0.98) : CGAffineTransformIdentity;
    }];
}

@end
