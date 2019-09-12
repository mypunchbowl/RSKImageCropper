//
// RSKImageCropViewController.m
//
// Copyright (c) 2014-present Ruslan Skorb, http://ruslanskorb.com/
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "RSKImageCropViewController.h"
#import "RSKTouchView.h"
#import "RSKImageScrollView.h"
#import "RSKInternalUtility.h"
#import "UIImage+RSKImageCropper.h"
#import "CGGeometry+RSKImageCropper.h"
#import "UIApplication+RSKImageCropper.h"

static const int kCropLines = 3;
static const CGFloat kResetAnimationDuration = 0.4;
static const CGFloat kLayoutImageScrollViewAnimationDuration = 0.25;

// K is a constant such that the accumulated error of our floating-point computations is definitely bounded by K units in the last place.
#ifdef CGFLOAT_IS_DOUBLE
    static const CGFloat kK = 9;
#else
    static const CGFloat kK = 0;
#endif

@interface RSKImageCropViewController () <UIGestureRecognizerDelegate>

@property (assign, nonatomic) BOOL originalNavigationControllerNavigationBarHidden;
@property (strong, nonatomic) UIImage *originalNavigationControllerNavigationBarShadowImage;
@property (copy, nonatomic) UIColor *originalNavigationControllerViewBackgroundColor;
@property (assign, nonatomic) BOOL originalStatusBarHidden;

@property (strong, nonatomic) RSKImageScrollView *imageScrollView;
@property (strong, nonatomic) RSKTouchView *overlayView;
@property (strong, nonatomic) CAShapeLayer *maskLayer;
@property (strong, nonatomic) CAShapeLayer *borderLayer;
@property (strong, nonatomic) UIView *lineView;

@property (nonatomic, strong) NSMutableArray *horizontalCropLines;
@property (nonatomic, strong) NSMutableArray *verticalCropLines;

@property (assign, nonatomic) CGRect maskRect;
@property (copy, nonatomic) UIBezierPath *maskPath;

@property (readonly, nonatomic) CGRect rectForMaskPath;
@property (readonly, nonatomic) CGRect rectForClipPath;

@property (strong, nonatomic) UILabel *moveAndScaleLabel;

@property (strong, nonatomic) UITapGestureRecognizer *doubleTapGestureRecognizer;
@property (strong, nonatomic) UIRotationGestureRecognizer *rotationGestureRecognizer;

@property (assign, nonatomic) BOOL didSetupConstraints;
@property (strong, nonatomic) NSLayoutConstraint *moveAndScaleLabelTopConstraint;

@end

@implementation RSKImageCropViewController

#pragma mark - Lifecycle

- (instancetype)init
{
    self = [super init];
    if (self) {
        _avoidEmptySpaceAroundImage = NO;
        _applyMaskToCroppedImage = NO;
        _maskLayerLineWidth = 1.0;
        _rotationEnabled = NO;
        _cropMode = RSKImageCropModeCircle;
        
        _portraitCircleMaskRectInnerEdgeInset = 15.0f;
        _portraitSquareMaskRectInnerEdgeInset = 20.0f;
        _portraitMoveAndScaleLabelTopAndCropViewTopVerticalSpace = 28.0f;
        _portraitCropViewBottomAndCancelButtonBottomVerticalSpace = 21.0f;
        _portraitCropViewBottomAndChooseButtonBottomVerticalSpace = 21.0f;
        _portraitCancelButtonLeadingAndCropViewLeadingHorizontalSpace = 13.0f;
        _portraitCropViewTrailingAndChooseButtonTrailingHorizontalSpace = 13.0;
        
        _landscapeCircleMaskRectInnerEdgeInset = 45.0f;
        _landscapeSquareMaskRectInnerEdgeInset = 45.0f;
        _landscapeMoveAndScaleLabelTopAndCropViewTopVerticalSpace = 12.0f;
        _landscapeCropViewBottomAndCancelButtonBottomVerticalSpace = 12.0f;
        _landscapeCropViewBottomAndChooseButtonBottomVerticalSpace = 12.0f;
        _landscapeCancelButtonLeadingAndCropViewLeadingHorizontalSpace = 13.0;
        _landscapeCropViewTrailingAndChooseButtonTrailingHorizontalSpace = 13.0;
    }
    return self;
}

- (instancetype)initWithImage:(UIImage *)originalImage
{
    self = [self init];
    if (self) {
        _originalImage = originalImage;
    }
    return self;
}

- (instancetype)initWithImage:(UIImage *)originalImage cropMode:(RSKImageCropMode)cropMode
{
    self = [self initWithImage:originalImage];
    if (self) {
        _cropMode = cropMode;
    }
    return self;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if ([self respondsToSelector:@selector(edgesForExtendedLayout)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    
    self.view.backgroundColor = [UIColor blackColor];
    self.view.clipsToBounds = YES;
    
    [self.view addSubview:self.imageScrollView];
    [self.view addSubview:self.overlayView];
    [self.view addSubview:self.moveAndScaleLabel];
    [self.view addSubview:self.lineView];
    [self configureToolbar];
    
    [self.view addGestureRecognizer:self.doubleTapGestureRecognizer];
    [self.view addGestureRecognizer:self.rotationGestureRecognizer];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    UIApplication *application = [UIApplication rsk_sharedApplication];
    if (application) {
        self.originalStatusBarHidden = application.statusBarHidden;
        [application setStatusBarHidden:YES];
    }
    
    self.originalNavigationControllerNavigationBarHidden = self.navigationController.navigationBarHidden;
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    
    self.originalNavigationControllerNavigationBarShadowImage = self.navigationController.navigationBar.shadowImage;
    self.navigationController.navigationBar.shadowImage = nil;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.originalNavigationControllerViewBackgroundColor = self.navigationController.view.backgroundColor;
    self.navigationController.view.backgroundColor = [UIColor blackColor];

    [self updateLines:self.horizontalCropLines horizontal:YES];
    [self updateLines:self.verticalCropLines horizontal:NO];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    UIApplication *application = [UIApplication rsk_sharedApplication];
    if (application) {
        [application setStatusBarHidden:self.originalStatusBarHidden];
    }
    
    [self.navigationController setNavigationBarHidden:self.originalNavigationControllerNavigationBarHidden animated:animated];
    self.navigationController.navigationBar.shadowImage = self.originalNavigationControllerNavigationBarShadowImage;
    self.navigationController.view.backgroundColor = self.originalNavigationControllerViewBackgroundColor;
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    [self updateMaskRect];
    [self layoutImageScrollView];
    [self layoutOverlayView];
    [self updateMaskPath];
    [self.view setNeedsUpdateConstraints];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    if (!self.imageScrollView.zoomView) {
        [self displayImage];
    }
}

- (void)updateViewConstraints
{
    [super updateViewConstraints];
    
    if (!self.didSetupConstraints) {
        // ---------------------------
        // The label "Move and Scale".
        // ---------------------------
        
        NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self.moveAndScaleLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual
                                                                         toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1.0f
                                                                       constant:0.0f];
        [self.view addConstraint:constraint];
        
        CGFloat constant = self.portraitMoveAndScaleLabelTopAndCropViewTopVerticalSpace;
        self.moveAndScaleLabelTopConstraint = [NSLayoutConstraint constraintWithItem:self.moveAndScaleLabel attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual
                                                                              toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0f
                                                                            constant:constant];
        [self.view addConstraint:self.moveAndScaleLabelTopConstraint];
        
        self.didSetupConstraints = YES;
    } else {
        if ([self isPortraitInterfaceOrientation]) {
            self.moveAndScaleLabelTopConstraint.constant = self.portraitMoveAndScaleLabelTopAndCropViewTopVerticalSpace;
        } else {
            self.moveAndScaleLabelTopConstraint.constant = self.landscapeMoveAndScaleLabelTopAndCropViewTopVerticalSpace;
        }
    }
}

#pragma mark - Punchbowl

- (void)configureToolbar {
    // Bottom Toolbar
    UIView *buttonView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 79, self.view.frame.size.width, 79)];
    buttonView.backgroundColor = [UIColor colorWithRed: 250.0 / 255.0 green: 250.0 / 255.0 blue: 248.0 / 255.0 alpha:1.0];
    [self.view addSubview:buttonView];

    UIButton *cancelButton = [self styledButton];
    [cancelButton setImage:self.cancelButtonImage forState:UIControlStateNormal];
    [buttonView addSubview:cancelButton];
    cancelButton.center = CGPointMake(self.view.frame.size.width / 6, 79.0 / 2.0);
    [cancelButton addTarget:self action:@selector(onCancelButtonTouch:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *cameraButton = [self styledButton];
    [cameraButton setImage:self.cameraButtonImage forState:UIControlStateNormal];
    [buttonView addSubview:cameraButton];
    cameraButton.center = CGPointMake(buttonView.frame.size.width / 2.0, buttonView.frame.size.height / 2.0);
    [cameraButton addTarget:self action:@selector(onCameraButtonTouch:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *doneButton = [self styledButton];
    [doneButton setImage:self.doneButtonImage forState:UIControlStateNormal];
    [buttonView addSubview:doneButton];
    doneButton.center = CGPointMake(self.view.frame.size.width - (self.view.frame.size.width / 6), 79.0 / 2.0);
    [doneButton addTarget:self action:@selector(onChooseButtonTouch:) forControlEvents:UIControlEventTouchUpInside];
}

- (UIButton *)styledButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    button.frame = CGRectMake(0, 0, 60, 60);
    button.layer.cornerRadius = button.frame.size.width / 2.0;
    button.layer.borderColor = [UIColor colorWithRed: 207.0 / 255.0 green: 204.0 / 255.0 blue: 187.0 / 255.0 alpha:0.7].CGColor;
    button.layer.borderWidth = 1.0;
    return button;
}

#pragma mark - Custom Accessors

- (RSKImageScrollView *)imageScrollView
{
    if (!_imageScrollView) {
        _imageScrollView = [[RSKImageScrollView alloc] init];
        _imageScrollView.clipsToBounds = NO;
        _imageScrollView.aspectFill = self.avoidEmptySpaceAroundImage;
    }
    return _imageScrollView;
}

- (RSKTouchView *)overlayView
{
    if (!_overlayView) {
        _overlayView = [[RSKTouchView alloc] init];
        _overlayView.receiver = self.imageScrollView;
        [_overlayView.layer addSublayer:self.maskLayer];
        [_overlayView.layer addSublayer:self.borderLayer];
    }
    return _overlayView;
}

- (CAShapeLayer *)maskLayer
{
    if (!_maskLayer) {
        _maskLayer = [CAShapeLayer layer];
        _maskLayer.fillRule = kCAFillRuleEvenOdd;
        _maskLayer.fillColor = self.maskLayerColor.CGColor;
        _maskLayer.lineWidth = self.maskLayerLineWidth;
        _maskLayer.strokeColor = self.maskLayerStrokeColor.CGColor;
    }
    return _maskLayer;
}

- (CAShapeLayer *)borderLayer
{
    if (!_borderLayer) {
        _borderLayer = [CAShapeLayer layer];
        _borderLayer.fillColor = [UIColor clearColor].CGColor;
        _borderLayer.strokeColor = [UIColor whiteColor].CGColor;
        _borderLayer.lineWidth = 3;
    }
    return _borderLayer;
}

- (UIColor *)maskLayerColor
{
    if (!_maskLayerColor) {
        _maskLayerColor = [UIColor colorWithRed:74.0 / 255.0 green: 74.0 / 255.0 blue: 74.0 / 255.0 alpha:0.85];
    }
    return _maskLayerColor;
}

- (UIColor *)gridLineColor
{
    if (!_gridLineColor) {
        _gridLineColor = [UIColor colorWithRed:250.0 / 255.0 green:250.0 / 255.0 blue:248.0 / 255.0 alpha:1.0];
    }
    return _gridLineColor;
}

- (UILabel *)moveAndScaleLabel
{
    if (!_moveAndScaleLabel) {
        _moveAndScaleLabel = [[UILabel alloc] init];
        _moveAndScaleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _moveAndScaleLabel.backgroundColor = [UIColor clearColor];
        _moveAndScaleLabel.text = @"Pinch and drag to position your photo";
        _moveAndScaleLabel.textAlignment = NSTextAlignmentCenter;
        _moveAndScaleLabel.textColor = [UIColor colorWithRed:237.0 / 255.0 green:237.0 / 255.0 blue:237.0 / 255.0 alpha:1.0];
        _moveAndScaleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16];
        _moveAndScaleLabel.opaque = NO;
    }
    return _moveAndScaleLabel;
}

- (UIView *)lineView {
    if (!_lineView) {
        _lineView = [[UIView alloc] initWithFrame:[self.dataSource imageCropViewControllerCustomMaskRect:self]];
        _lineView.backgroundColor = [UIColor clearColor];
        _lineView.userInteractionEnabled = NO;

        _horizontalCropLines = [NSMutableArray array];
        for (int i = 0; i < kCropLines; i++) {
            UIView *line = [UIView new];
            line.backgroundColor = self.gridLineColor;
            line.alpha = 1.0;
            [_horizontalCropLines addObject:line];
            [_lineView addSubview:line];
        }

        _verticalCropLines = [NSMutableArray array];
        for (int i = 0; i < kCropLines; i++) {
            UIView *line = [UIView new];
            line.backgroundColor = self.gridLineColor;
            line.alpha = 1.0;
            [_verticalCropLines addObject:line];
            [_lineView addSubview:line];
        }
    }
    return _lineView;
}

- (UITapGestureRecognizer *)doubleTapGestureRecognizer
{
    if (!_doubleTapGestureRecognizer) {
        _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        _doubleTapGestureRecognizer.delaysTouchesEnded = NO;
        _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
        _doubleTapGestureRecognizer.delegate = self;
    }
    return _doubleTapGestureRecognizer;
}

- (UIRotationGestureRecognizer *)rotationGestureRecognizer
{
    if (!_rotationGestureRecognizer) {
        _rotationGestureRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
        _rotationGestureRecognizer.delaysTouchesEnded = NO;
        _rotationGestureRecognizer.delegate = self;
        _rotationGestureRecognizer.enabled = self.isRotationEnabled;
    }
    return _rotationGestureRecognizer;
}

- (CGRect)cropRect
{
    CGRect cropRect = CGRectZero;
    float zoomScale = 1.0 / self.imageScrollView.zoomScale;
    
    cropRect.origin.x = round(self.imageScrollView.contentOffset.x * zoomScale);
    cropRect.origin.y = round(self.imageScrollView.contentOffset.y * zoomScale);
    cropRect.size.width = CGRectGetWidth(self.imageScrollView.bounds) * zoomScale;
    cropRect.size.height = CGRectGetHeight(self.imageScrollView.bounds) * zoomScale;
    
    CGFloat width = CGRectGetWidth(cropRect);
    CGFloat height = CGRectGetHeight(cropRect);
    CGFloat ceilWidth = ceil(width);
    CGFloat ceilHeight = ceil(height);
    
    if (fabs(ceilWidth - width) < pow(10, kK) * RSK_EPSILON * fabs(ceilWidth + width) || fabs(ceilWidth - width) < RSK_MIN ||
        fabs(ceilHeight - height) < pow(10, kK) * RSK_EPSILON * fabs(ceilHeight + height) || fabs(ceilHeight - height) < RSK_MIN) {
        
        cropRect.size.width = ceilWidth;
        cropRect.size.height = ceilHeight;
    } else {
        cropRect.size.width = floor(width);
        cropRect.size.height = floor(height);
    }
    
    return cropRect;
}

- (CGRect)rectForClipPath
{
    if (!self.maskLayerStrokeColor) {
        return self.overlayView.frame;
    } else {
        CGFloat maskLayerLineHalfWidth = self.maskLayerLineWidth / 2.0;
        return CGRectInset(self.overlayView.frame, -maskLayerLineHalfWidth, -maskLayerLineHalfWidth);
    }
}

- (CGRect)rectForMaskPath
{
    if (!self.maskLayerStrokeColor) {
        return self.maskRect;
    } else {
        CGFloat maskLayerLineHalfWidth = self.maskLayerLineWidth / 2.0;
        return CGRectInset(self.maskRect, maskLayerLineHalfWidth, maskLayerLineHalfWidth);
    }
}

- (CGFloat)rotationAngle
{
    CGAffineTransform transform = self.imageScrollView.transform;
    CGFloat rotationAngle = atan2(transform.b, transform.a);
    return rotationAngle;
}

- (CGFloat)zoomScale
{
    return self.imageScrollView.zoomScale;
}

- (void)setAvoidEmptySpaceAroundImage:(BOOL)avoidEmptySpaceAroundImage
{
    if (_avoidEmptySpaceAroundImage != avoidEmptySpaceAroundImage) {
        _avoidEmptySpaceAroundImage = avoidEmptySpaceAroundImage;
        
        self.imageScrollView.aspectFill = avoidEmptySpaceAroundImage;
    }
}

- (void)setCropMode:(RSKImageCropMode)cropMode
{
    if (_cropMode != cropMode) {
        _cropMode = cropMode;
        
        if (self.imageScrollView.zoomView) {
            [self reset:NO];
        }
    }
}

- (void)setOriginalImage:(UIImage *)originalImage
{
    if (![_originalImage isEqual:originalImage]) {
        _originalImage = originalImage;
        if (self.isViewLoaded && self.view.window) {
            [self displayImage];
        }
    }
}

- (void)setMaskPath:(UIBezierPath *)maskPath
{
    if (![_maskPath isEqual:maskPath]) {
        _maskPath = maskPath;
        self.borderLayer.path = [maskPath CGPath];

        UIBezierPath *clipPath = [UIBezierPath bezierPathWithRect:self.rectForClipPath];
        [clipPath appendPath:maskPath];
        clipPath.usesEvenOddFillRule = YES;
        
        CABasicAnimation *pathAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
        pathAnimation.duration = [CATransaction animationDuration];
        pathAnimation.timingFunction = [CATransaction animationTimingFunction];
        [self.maskLayer addAnimation:pathAnimation forKey:@"path"];
        
        self.maskLayer.path = [clipPath CGPath];
    }
}

- (void)setRotationAngle:(CGFloat)rotationAngle
{
    if (self.rotationAngle != rotationAngle) {
        CGFloat rotation = (rotationAngle - self.rotationAngle);
        CGAffineTransform transform = CGAffineTransformRotate(self.imageScrollView.transform, rotation);
        self.imageScrollView.transform = transform;
    }
}

- (void)setRotationEnabled:(BOOL)rotationEnabled
{
    if (_rotationEnabled != rotationEnabled) {
        _rotationEnabled = rotationEnabled;
        
        self.rotationGestureRecognizer.enabled = rotationEnabled;
    }
}

- (void)setZoomScale:(CGFloat)zoomScale
{
    self.imageScrollView.zoomScale = zoomScale;
}

#pragma mark - Action handling

- (void)onCancelButtonTouch:(UIButton *)sender
{
    [self cancelCrop];
}

- (void)onCameraButtonTouch:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(imageCropViewControllerDidSelectCameraButton:)]) {
        [self.delegate imageCropViewControllerDidSelectCameraButton:self];
    }
}

- (void)onChooseButtonTouch:(UIButton *)sender
{
    [self cropImage];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gestureRecognizer
{
    [self reset:YES];
}

- (void)handleRotation:(UIRotationGestureRecognizer *)gestureRecognizer
{
    [self setRotationAngle:(self.rotationAngle + gestureRecognizer.rotation)];
    gestureRecognizer.rotation = 0;
    
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [UIView animateWithDuration:kLayoutImageScrollViewAnimationDuration
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             [self layoutImageScrollView];
                         }
                         completion:nil];
    }
}

- (void)updateLines:(NSArray *)lines horizontal:(BOOL)horizontal
{
    [lines enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIView *line = (UIView *)obj;
        if (horizontal) {
            line.frame = CGRectMake(0,
                                    (self.lineView.frame.size.height / (lines.count + 1)) * (idx + 1),
                                    self.lineView.frame.size.width,
                                    1 / [UIScreen mainScreen].scale);
        } else {
            line.frame = CGRectMake((self.lineView.frame.size.width / (lines.count + 1)) * (idx + 1),
                                    0,
                                    1 / [UIScreen mainScreen].scale,
                                    self.lineView.frame.size.height);
        }
    }];
}

#pragma mark - Public

- (BOOL)isPortraitInterfaceOrientation
{
    return CGRectGetHeight(self.view.bounds) > CGRectGetWidth(self.view.bounds);
}

#pragma mark - Private

- (void)reset:(BOOL)animated
{
    if (animated) {
        [UIView beginAnimations:@"rsk_reset" context:NULL];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
        [UIView setAnimationDuration:kResetAnimationDuration];
        [UIView setAnimationBeginsFromCurrentState:YES];
    }
    
    [self resetRotation];
    [self resetFrame];
    [self resetZoomScale];
    [self resetContentOffset];
    
    if (animated) {
        [UIView commitAnimations];
    }
}

- (void)resetContentOffset
{
    CGSize boundsSize = self.imageScrollView.bounds.size;
    CGRect frameToCenter = self.imageScrollView.zoomView.frame;
    
    CGPoint contentOffset;
    if (CGRectGetWidth(frameToCenter) > boundsSize.width) {
        contentOffset.x = (CGRectGetWidth(frameToCenter) - boundsSize.width) * 0.5f;
    } else {
        contentOffset.x = 0;
    }
    if (CGRectGetHeight(frameToCenter) > boundsSize.height) {
        contentOffset.y = (CGRectGetHeight(frameToCenter) - boundsSize.height) * 0.5f;
    } else {
        contentOffset.y = 0;
    }
    
    self.imageScrollView.contentOffset = contentOffset;
}

- (void)resetFrame
{
    [self layoutImageScrollView];
}

- (void)resetRotation
{
    [self setRotationAngle:0.0];
}

- (void)resetZoomScale
{
    CGFloat zoomScale;
    if (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds)) {
        zoomScale = CGRectGetHeight(self.view.bounds) / self.originalImage.size.height;
    } else {
        zoomScale = CGRectGetWidth(self.view.bounds) / self.originalImage.size.width;
    }
    self.imageScrollView.zoomScale = zoomScale;
}

- (NSArray *)intersectionPointsOfLineSegment:(RSKLineSegment)lineSegment withRect:(CGRect)rect
{
    RSKLineSegment top = RSKLineSegmentMake(CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)),
                                            CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)));
    
    RSKLineSegment right = RSKLineSegmentMake(CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)),
                                              CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)));
    
    RSKLineSegment bottom = RSKLineSegmentMake(CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)),
                                               CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)));
    
    RSKLineSegment left = RSKLineSegmentMake(CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)),
                                             CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)));
    
    CGPoint p0 = RSKLineSegmentIntersection(top, lineSegment);
    CGPoint p1 = RSKLineSegmentIntersection(right, lineSegment);
    CGPoint p2 = RSKLineSegmentIntersection(bottom, lineSegment);
    CGPoint p3 = RSKLineSegmentIntersection(left, lineSegment);
    
    NSMutableArray *intersectionPoints = [@[] mutableCopy];
    if (!RSKPointIsNull(p0)) {
        [intersectionPoints addObject:[NSValue valueWithCGPoint:p0]];
    }
    if (!RSKPointIsNull(p1)) {
        [intersectionPoints addObject:[NSValue valueWithCGPoint:p1]];
    }
    if (!RSKPointIsNull(p2)) {
        [intersectionPoints addObject:[NSValue valueWithCGPoint:p2]];
    }
    if (!RSKPointIsNull(p3)) {
        [intersectionPoints addObject:[NSValue valueWithCGPoint:p3]];
    }
    
    return [intersectionPoints copy];
}

- (void)displayImage
{
    if (self.originalImage) {
        [self.imageScrollView displayImage:self.originalImage];
        [self reset:NO];
    }
}

- (void)layoutImageScrollView
{
    CGRect frame = CGRectZero;
    
    // The bounds of the image scroll view should always fill the mask area.
    switch (self.cropMode) {
        case RSKImageCropModeSquare: {
            if (self.rotationAngle == 0.0) {
                frame = self.maskRect;
            } else {
                // Step 1: Rotate the left edge of the initial rect of the image scroll view clockwise around the center by `rotationAngle`.
                CGRect initialRect = self.maskRect;
                CGFloat rotationAngle = self.rotationAngle;
                
                CGPoint leftTopPoint = CGPointMake(initialRect.origin.x, initialRect.origin.y);
                CGPoint leftBottomPoint = CGPointMake(initialRect.origin.x, initialRect.origin.y + initialRect.size.height);
                RSKLineSegment leftLineSegment = RSKLineSegmentMake(leftTopPoint, leftBottomPoint);
                
                CGPoint pivot = RSKRectCenterPoint(initialRect);
                
                CGFloat alpha = fabs(rotationAngle);
                RSKLineSegment rotatedLeftLineSegment = RSKLineSegmentRotateAroundPoint(leftLineSegment, pivot, alpha);
                
                // Step 2: Find the points of intersection of the rotated edge with the initial rect.
                NSArray *points = [self intersectionPointsOfLineSegment:rotatedLeftLineSegment withRect:initialRect];
                
                // Step 3: If the number of intersection points more than one
                // then the bounds of the rotated image scroll view does not completely fill the mask area.
                // Therefore, we need to update the frame of the image scroll view.
                // Otherwise, we can use the initial rect.
                if (points.count > 1) {
                    // We have a right triangle.
                    
                    // Step 4: Calculate the altitude of the right triangle.
                    if ((alpha > M_PI_2) && (alpha < M_PI)) {
                        alpha = alpha - M_PI_2;
                    } else if ((alpha > (M_PI + M_PI_2)) && (alpha < (M_PI + M_PI))) {
                        alpha = alpha - (M_PI + M_PI_2);
                    }
                    CGFloat sinAlpha = sin(alpha);
                    CGFloat cosAlpha = cos(alpha);
                    CGFloat hypotenuse = RSKPointDistance([points[0] CGPointValue], [points[1] CGPointValue]);
                    CGFloat altitude = hypotenuse * sinAlpha * cosAlpha;
                    
                    // Step 5: Calculate the target width.
                    CGFloat initialWidth = CGRectGetWidth(initialRect);
                    CGFloat targetWidth = initialWidth + altitude * 2;
                    
                    // Step 6: Calculate the target frame.
                    CGFloat scale = targetWidth / initialWidth;
                    CGPoint center = RSKRectCenterPoint(initialRect);
                    frame = RSKRectScaleAroundPoint(initialRect, center, scale, scale);
                    
                    // Step 7: Avoid floats.
                    frame.origin.x = round(CGRectGetMinX(frame));
                    frame.origin.y = round(CGRectGetMinY(frame));
                    frame = CGRectIntegral(frame);
                } else {
                    // Step 4: Use the initial rect.
                    frame = initialRect;
                }
            }
            break;
        }
        case RSKImageCropModeCircle: {
            frame = self.maskRect;
            break;
        }
        case RSKImageCropModeCustom: {
            if ([self.dataSource respondsToSelector:@selector(imageCropViewControllerCustomMovementRect:)]) {
                frame = [self.dataSource imageCropViewControllerCustomMovementRect:self];
            } else {
                // Will be changed to `CGRectNull` in version `2.0.0`.
                frame = self.maskRect;
            }
            break;
        }
    }
    
    CGAffineTransform transform = self.imageScrollView.transform;
    self.imageScrollView.transform = CGAffineTransformIdentity;
    self.imageScrollView.frame = frame;
    self.imageScrollView.transform = transform;
}

- (void)layoutOverlayView
{
    CGRect frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds) * 2, CGRectGetHeight(self.view.bounds) * 2);
    self.overlayView.frame = frame;
}

- (void)updateMaskRect
{
    switch (self.cropMode) {
        case RSKImageCropModeCircle: {
            CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
            CGFloat viewHeight = CGRectGetHeight(self.view.bounds);
            
            CGFloat diameter;
            if ([self isPortraitInterfaceOrientation]) {
                diameter = MIN(viewWidth, viewHeight) - self.portraitCircleMaskRectInnerEdgeInset * 2;
            } else {
                diameter = MIN(viewWidth, viewHeight) - self.landscapeCircleMaskRectInnerEdgeInset * 2;
            }
            
            CGSize maskSize = CGSizeMake(diameter, diameter);
            
            self.maskRect = CGRectMake((viewWidth - maskSize.width) * 0.5f,
                                       (viewHeight - maskSize.height) * 0.5f,
                                       maskSize.width,
                                       maskSize.height);
            break;
        }
        case RSKImageCropModeSquare: {
            CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
            CGFloat viewHeight = CGRectGetHeight(self.view.bounds);
            
            CGFloat length;
            if ([self isPortraitInterfaceOrientation]) {
                length = MIN(viewWidth, viewHeight) - self.portraitSquareMaskRectInnerEdgeInset * 2;
            } else {
                length = MIN(viewWidth, viewHeight) - self.landscapeSquareMaskRectInnerEdgeInset * 2;
            }
            
            CGSize maskSize = CGSizeMake(length, length);
            
            self.maskRect = CGRectMake((viewWidth - maskSize.width) * 0.5f,
                                       (viewHeight - maskSize.height) * 0.5f,
                                       maskSize.width,
                                       maskSize.height);
            break;
        }
        case RSKImageCropModeCustom: {
            self.maskRect = [self.dataSource imageCropViewControllerCustomMaskRect:self];
            self.lineView.frame = self.maskRect;
            break;
        }
    }
}

- (void)updateMaskPath
{
    switch (self.cropMode) {
        case RSKImageCropModeCircle: {
            self.maskPath = [UIBezierPath bezierPathWithOvalInRect:self.rectForMaskPath];
            break;
        }
        case RSKImageCropModeSquare: {
            self.maskPath = [UIBezierPath bezierPathWithRect:self.rectForMaskPath];
            break;
        }
        case RSKImageCropModeCustom: {
            self.maskPath = [self.dataSource imageCropViewControllerCustomMaskPath:self];
            break;
        }
    }
}

- (UIImage *)croppedImage:(UIImage *)image cropRect:(CGRect)cropRect scale:(CGFloat)imageScale orientation:(UIImageOrientation)imageOrientation
{
    if (!image.images) {
        CGImageRef croppedCGImage = CGImageCreateWithImageInRect(image.CGImage, cropRect);
        UIImage *croppedImage = [UIImage imageWithCGImage:croppedCGImage scale:imageScale orientation:imageOrientation];
        CGImageRelease(croppedCGImage);
        return croppedImage;
    } else {
        UIImage *animatedImage = image;
        NSMutableArray *croppedImages = [NSMutableArray array];
        for (UIImage *image in animatedImage.images) {
            UIImage *croppedImage = [self croppedImage:image cropRect:cropRect scale:imageScale orientation:imageOrientation];
            [croppedImages addObject:croppedImage];
        }
        return [UIImage animatedImageWithImages:croppedImages duration:image.duration];
    }
}

- (UIImage *)croppedImage:(UIImage *)image cropMode:(RSKImageCropMode)cropMode cropRect:(CGRect)cropRect rotationAngle:(CGFloat)rotationAngle zoomScale:(CGFloat)zoomScale maskPath:(UIBezierPath *)maskPath applyMaskToCroppedImage:(BOOL)applyMaskToCroppedImage
{
    // Step 1: check and correct the crop rect.
    CGSize imageSize = image.size;
    CGFloat x = CGRectGetMinX(cropRect);
    CGFloat y = CGRectGetMinY(cropRect);
    CGFloat width = CGRectGetWidth(cropRect);
    CGFloat height = CGRectGetHeight(cropRect);
    
    UIImageOrientation imageOrientation = image.imageOrientation;
    if (imageOrientation == UIImageOrientationRight || imageOrientation == UIImageOrientationRightMirrored) {
        cropRect.origin.x = y;
        cropRect.origin.y = round(imageSize.width - CGRectGetWidth(cropRect) - x);
        cropRect.size.width = height;
        cropRect.size.height = width;
    } else if (imageOrientation == UIImageOrientationLeft || imageOrientation == UIImageOrientationLeftMirrored) {
        cropRect.origin.x = round(imageSize.height - CGRectGetHeight(cropRect) - y);
        cropRect.origin.y = x;
        cropRect.size.width = height;
        cropRect.size.height = width;
    } else if (imageOrientation == UIImageOrientationDown || imageOrientation == UIImageOrientationDownMirrored) {
        cropRect.origin.x = round(imageSize.width - CGRectGetWidth(cropRect) - x);
        cropRect.origin.y = round(imageSize.height - CGRectGetHeight(cropRect) - y);
    }
    
    CGFloat imageScale = image.scale;
    cropRect = CGRectApplyAffineTransform(cropRect, CGAffineTransformMakeScale(imageScale, imageScale));
    
    // Step 2: create an image using the data contained within the specified rect.
    UIImage *croppedImage = [self croppedImage:image cropRect:cropRect scale:imageScale orientation:imageOrientation];
    
    // Step 3: fix orientation of the cropped image.
    croppedImage = [croppedImage fixOrientation];
    imageOrientation = croppedImage.imageOrientation;
    
    // Step 4: If current mode is `RSKImageCropModeSquare` and the image is not rotated
    // or mask should not be applied to the image after cropping and the image is not rotated,
    // we can return the cropped image immediately.
    // Otherwise, we must further process the image.
    if ((cropMode == RSKImageCropModeSquare || !applyMaskToCroppedImage) && rotationAngle == 0.0) {
        // Step 5: return the cropped image immediately.
        return croppedImage;
    } else {
        // Step 5: create a new context.
        CGSize maskSize = CGRectIntegral(maskPath.bounds).size;
        CGSize contextSize = CGSizeMake(ceil(maskSize.width / zoomScale),
                                        ceil(maskSize.height / zoomScale));
        UIGraphicsBeginImageContextWithOptions(contextSize, NO, imageScale);
        
        // Step 6: apply the mask if needed.
        if (applyMaskToCroppedImage) {
            // 6a: scale the mask to the size of the crop rect.
            UIBezierPath *maskPathCopy = [maskPath copy];
            CGFloat scale = 1 / zoomScale;
            [maskPathCopy applyTransform:CGAffineTransformMakeScale(scale, scale)];
            
            // 6b: move the mask to the top-left.
            CGPoint translation = CGPointMake(-CGRectGetMinX(maskPathCopy.bounds),
                                              -CGRectGetMinY(maskPathCopy.bounds));
            [maskPathCopy applyTransform:CGAffineTransformMakeTranslation(translation.x, translation.y)];
            
            // 6c: apply the mask.
            [maskPathCopy addClip];
        }
        
        // Step 7: rotate the cropped image if needed.
        if (rotationAngle != 0) {
            croppedImage = [croppedImage rotateByAngle:rotationAngle];
        }
        
        // Step 8: draw the cropped image.
        CGPoint point = CGPointMake(round((contextSize.width - croppedImage.size.width) * 0.5f),
                                    round((contextSize.height - croppedImage.size.height) * 0.5f));
        [croppedImage drawAtPoint:point];
        
        // Step 9: get the cropped image affter processing from the context.
        croppedImage = UIGraphicsGetImageFromCurrentImageContext();
        
        // Step 10: remove the context.
        UIGraphicsEndImageContext();
        
        croppedImage = [UIImage imageWithCGImage:croppedImage.CGImage scale:imageScale orientation:imageOrientation];
        
        // Step 11: return the cropped image affter processing.
        return croppedImage;
    }
}

- (void)cropImage
{
    UILabel *label = [[UILabel alloc]initWithFrame:CGRectMake(80, 250, 30, 40)];
    label.text = @"1";
    [label setFont:[UIFont boldSystemFontOfSize:16]];
    [label setTextColor:[UIColor redColor]];
    [self.view addSubview:label];

    if ([self.delegate respondsToSelector:@selector(imageCropViewController:willCropImage:)]) {
        [self.delegate imageCropViewController:self willCropImage:self.originalImage];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{

            CGRect cropRect = self.cropRect;
            UILabel *label2 = [[UILabel alloc]initWithFrame:CGRectMake(110, 250, 30, 40)];
            label2.text = @"2";
            [label2 setFont:[UIFont boldSystemFontOfSize:16]];
            [label2 setTextColor:[UIColor redColor]];
            [self.view addSubview:label2];
            CGFloat rotationAngle = self.rotationAngle;

            UILabel *label3 = [[UILabel alloc]initWithFrame:CGRectMake(150, 250, 30, 40)];
            label3.text = @"3";
            [label3 setFont:[UIFont boldSystemFontOfSize:16]];
            [label3 setTextColor:[UIColor redColor]];
            [self.view addSubview:label3];

            UIImage *croppedImage = [self croppedImage:self.originalImage cropMode:self.cropMode cropRect:cropRect rotationAngle:rotationAngle zoomScale:self.imageScrollView.zoomScale maskPath:self.maskPath applyMaskToCroppedImage:self.applyMaskToCroppedImage];

            UILabel *label4 = [[UILabel alloc]initWithFrame:CGRectMake(190, 250, 30, 40)];
            label4.text = @"4";
            [label4 setFont:[UIFont boldSystemFontOfSize:16]];
            [label4 setTextColor:[UIColor redColor]];
            [self.view addSubview:label4];


            if ([self.delegate respondsToSelector:@selector(imageCropViewController:didCropImage:usingCropRect:rotationAngle:)]) {
                UILabel *label6 = [[UILabel alloc]initWithFrame:CGRectMake(150, 300, 30, 40)];
                label6.text = @"6";
                [label6 setFont:[UIFont boldSystemFontOfSize:16]];
                [label6 setTextColor:[UIColor redColor]];
                [self.view addSubview:label6];
                [self.delegate imageCropViewController:self didCropImage:croppedImage usingCropRect:cropRect rotationAngle:rotationAngle];
            } else if ([self.delegate respondsToSelector:@selector(imageCropViewController:didCropImage:usingCropRect:)]) {
                UILabel *label7 = [[UILabel alloc]initWithFrame:CGRectMake(190, 300, 30, 40)];
                label7.text = @"7";
                [label7 setFont:[UIFont boldSystemFontOfSize:16]];
                [label7 setTextColor:[UIColor redColor]];
                [self.view addSubview:label7];
                [self.delegate imageCropViewController:self didCropImage:croppedImage usingCropRect:cropRect];
            }
            UILabel *label5 = [[UILabel alloc]initWithFrame:CGRectMake(230, 250, 30, 40)];
            label5.text = @"5";
            [label5 setFont:[UIFont boldSystemFontOfSize:16]];
            [label5 setTextColor:[UIColor redColor]];
            [self.view addSubview:label5];
        });
    });

    UILabel *labelFinish = [[UILabel alloc]initWithFrame:CGRectMake(295, 250, 100, 40)];
    labelFinish.text = @"Finished";
    [labelFinish setFont:[UIFont boldSystemFontOfSize:16]];
    [labelFinish setTextColor:[UIColor redColor]];
    [self.view addSubview:labelFinish];
}

- (void)cancelCrop
{
    if ([self.delegate respondsToSelector:@selector(imageCropViewControllerDidCancelCrop:)]) {
        [self.delegate imageCropViewControllerDidCancelCrop:self];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

@end
