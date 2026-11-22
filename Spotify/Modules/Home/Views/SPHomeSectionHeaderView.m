//
//  SPHomeSectionHeaderView.m
//  Spotify
//

#import "SPHomeSectionHeaderView.h"

@interface SPHomeSectionHeaderView ()
@property (nonatomic, strong) UILabel *titleLabel;
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
            make.left.right.equalTo(self);
            make.bottom.equalTo(self).offset(-8);
        }];
    }
    return self;
}

@end
