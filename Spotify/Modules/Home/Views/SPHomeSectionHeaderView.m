//
//  SPHomeSectionHeaderView.m
//  Spotify
//

#import "SPHomeSectionHeaderView.h"

@interface SPHomeSectionHeaderView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) MASConstraint *leftConstraint;
@property (nonatomic, strong) MASConstraint *rightConstraint;
@end

@implementation SPHomeSectionHeaderView

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _titleLabel = [UILabel new];
        _titleLabel.font = SPTheme.sectionTitleFont;
        _titleLabel.textColor = SPTheme.textPrimaryColor;
        [self addSubview:_titleLabel];
        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            self.leftConstraint = make.left.equalTo(self).offset(0);
            self.rightConstraint = make.right.equalTo(self).offset(0);
            make.bottom.equalTo(self).offset(-8);
        }];
    }
    return self;
}

- (void)setHorizontalInset:(CGFloat)horizontalInset {
    if (_horizontalInset == horizontalInset) return;
    _horizontalInset = horizontalInset;
    self.leftConstraint.offset(horizontalInset);
    self.rightConstraint.offset(-horizontalInset);
}

@end
