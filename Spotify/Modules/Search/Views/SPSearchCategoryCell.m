//
//  SPSearchCategoryCell.m
//  Spotify
//

#import "SPSearchCategoryCell.h"

@interface SPSearchCategoryCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *coverShadowContainer;
@property (nonatomic, strong) UIImageView *coverView;
@end

@implementation SPSearchCategoryCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.layer.cornerRadius = 6;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;

        _coverShadowContainer = [UIView new];
        _coverShadowContainer.layer.shadowColor = UIColor.blackColor.CGColor;
        _coverShadowContainer.layer.shadowOpacity = 0.28;
        _coverShadowContainer.layer.shadowRadius = 6;
        _coverShadowContainer.layer.shadowOffset = CGSizeMake(-2, 4);
        _coverShadowContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 68, 68) cornerRadius:4].CGPath;
        [self.contentView addSubview:_coverShadowContainer];

        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 4;
        [_coverShadowContainer addSubview:_coverView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakStrategy = NSLineBreakStrategyStandard;
        [self.contentView addSubview:_titleLabel];

        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(12);
            make.left.equalTo(self.contentView).offset(12);
            make.right.lessThanOrEqualTo(self.coverShadowContainer.mas_left).offset(-4);
        }];
        [_coverShadowContainer mas_makeConstraints:^(MASConstraintMaker *make) {
            make.size.mas_equalTo(CGSizeMake(68, 68));
            make.right.equalTo(self.contentView).offset(10);
            make.bottom.equalTo(self.contentView).offset(8);
        }];
        [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.coverShadowContainer);
        }];
        _coverShadowContainer.transform = CGAffineTransformMakeRotation(0.42);
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.coverView sp_cancelCoverLoadAndReset];
}

- (void)configureWithCategory:(SPSearchCategory *)category {
    self.titleLabel.text = category.name;
    self.contentView.backgroundColor = [UIColor sp_colorWithHexString:category.colorHex] ?: SPTheme.highlightColor;
    [self.coverView sp_setImageWithURLString:category.coverURL placeholderColor:self.contentView.backgroundColor];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:0.15
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        if (!reduceMotion) {
            self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
        }
        self.contentView.alpha = highlighted ? 0.85 : 1.0;
    } completion:nil];
}

@end
