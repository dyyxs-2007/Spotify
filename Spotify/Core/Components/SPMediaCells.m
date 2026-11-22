//
//  SPMediaCells.m
//  Spotify
//

#import "SPMediaCells.h"

#pragma mark - SPMediaRowCell

@interface SPMediaRowCell ()
@property (nonatomic, strong) SPMediaRowView *rowView;
@property (nonatomic, strong) UIButton *moreButton;
@end

@implementation SPMediaRowCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        UIView *selected = [UIView new];
        selected.backgroundColor = SPTheme.highlightColor;
        self.selectedBackgroundView = selected;

        _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_moreButton setImage:[SPTheme symbol:@"ellipsis" size:16 weight:UIImageSymbolWeightBold] forState:UIControlStateNormal];
        _moreButton.tintColor = SPTheme.textSecondaryColor;
        [_moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_moreButton];

        _rowView = [SPMediaRowView new];
        _rowView.userInteractionEnabled = NO;
        [self.contentView addSubview:_rowView];

        [_moreButton mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self.contentView).offset(-4);
            make.centerY.equalTo(self.contentView);
            make.size.mas_equalTo(CGSizeMake(44, 44));
        }];
        self.showsMoreButton = YES;
    }
    return self;
}

- (void)setShowsMoreButton:(BOOL)showsMoreButton {
    _showsMoreButton = showsMoreButton;
    self.moreButton.hidden = !showsMoreButton;
    [self.rowView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.contentView).offset(SPMarginHorizontal);
        make.top.equalTo(self.contentView).offset(8);
        make.bottom.equalTo(self.contentView).offset(-8);
        if (showsMoreButton) make.right.equalTo(self.moreButton.mas_left).offset(-4);
        else make.right.equalTo(self.contentView).offset(-SPMarginHorizontal);
    }];
}

- (void)moreTapped {
    if (self.moreHandler) self.moreHandler();
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.moreHandler = nil;
    self.rowView.active = NO;
}

@end

#pragma mark - SPMediaRowCollectionCell

@interface SPMediaRowCollectionCell ()
@property (nonatomic, strong) SPMediaRowView *rowView;
@end

@implementation SPMediaRowCollectionCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _rowView = [SPMediaRowView new];
        _rowView.coverSize = 64;
        [self.contentView addSubview:_rowView];
        [_rowView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.contentView);
        }];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.6 : 1;
}

@end

#pragma mark - SPMediaCardCell

@interface SPMediaCardCell ()
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation SPMediaCardCell

+ (NSString *)reuseId { return NSStringFromClass(self); }

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 6;
        [self.contentView addSubview:_coverView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [SPTheme fontOfSize:13 weight:UIFontWeightSemibold];
        _titleLabel.textColor = SPTheme.textPrimaryColor;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [SPTheme fontOfSize:12 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = SPTheme.textSecondaryColor;
        _subtitleLabel.numberOfLines = 2;
        [self.contentView addSubview:_subtitleLabel];

        [_coverView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.equalTo(self.contentView);
            make.height.equalTo(self.coverView.mas_width);
        }];
        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.coverView.mas_bottom).offset(8);
            make.left.right.equalTo(self.contentView);
        }];
        [_subtitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.titleLabel.mas_bottom).offset(3);
            make.left.right.equalTo(self.contentView);
            make.bottom.lessThanOrEqualTo(self.contentView);
        }];
    }
    return self;
}

- (void)configureWithItem:(id<SPMediaItem>)item {
    BOOL circular = item.mediaType == SPMediaTypeArtist;
    self.titleLabel.text = item.title;
    self.subtitleLabel.text = item.subtitle;
    self.titleLabel.textAlignment = circular ? NSTextAlignmentCenter : NSTextAlignmentNatural;
    self.subtitleLabel.textAlignment = self.titleLabel.textAlignment;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    self.coverView.layer.cornerRadius = circular ? CGRectGetWidth(self.coverView.bounds) / 2 : 6;
    [self.coverView sp_setCoverWithItem:item];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL circular = (self.titleLabel.textAlignment == NSTextAlignmentCenter);
    self.coverView.layer.cornerRadius = circular ? CGRectGetWidth(self.coverView.bounds) / 2.0 : 6.0;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.15 animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
        self.contentView.alpha = highlighted ? 0.75 : 1;
    }];
}

@end
