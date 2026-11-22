//
//  SPSearchCategoryCell.m
//  Spotify
//

#import "SPSearchCategoryCell.h"

@interface SPSearchCategoryCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *coverView;
@end

@implementation SPSearchCategoryCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.layer.cornerRadius = 6;
        self.contentView.clipsToBounds = YES;

        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 4;
        [self.contentView addSubview:_coverView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:16 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.numberOfLines = 2;
        [self.contentView addSubview:_titleLabel];

        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(12);
            make.left.equalTo(self.contentView).offset(12);
            make.right.lessThanOrEqualTo(self.coverView.mas_left).offset(-4);
        }];
        [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.size.mas_equalTo(CGSizeMake(68, 68));
            make.right.equalTo(self.contentView).offset(10);
            make.bottom.equalTo(self.contentView).offset(8);
        }];
        _coverView.transform = CGAffineTransformMakeRotation(0.42);
    }
    return self;
}

- (void)configureWithCategory:(SPSearchCategory *)category {
    self.titleLabel.text = category.name;
    self.contentView.backgroundColor = [UIColor sp_colorWithHexString:category.colorHex] ?: SPTheme.highlightColor;
    [self.coverView sp_setImageWithURLString:category.coverURL placeholderColor:self.contentView.backgroundColor];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
        self.contentView.alpha = highlighted ? 0.85 : 1.0;
    }];
}

@end
