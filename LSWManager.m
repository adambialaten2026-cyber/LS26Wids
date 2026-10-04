#import "LSW.h"
#import <objc/runtime.h>
#import <notify.h>

static NSString *const kWidgets = @"widgets";   // NSArray<NSString*> ordered identifiers

#pragma mark - Picker (list of available widgets, live previews)

@interface LSWPicker : UIView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) void (^onPick)(NSString *ident);
@property (nonatomic, strong) UITableView *table;
@end

@implementation LSWPicker
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        blur.frame = self.bounds; blur.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:blur];
        self.layer.cornerRadius = 28; self.clipsToBounds = YES;
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0, 14, f.size.width, 24)];
        t.text = @"Add Widgets"; t.textAlignment = NSTextAlignmentCenter; t.textColor = UIColor.whiteColor;
        t.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        t.autoresizingMask = UIViewAutoresizingFlexibleWidth; [self addSubview:t];
        _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 48, f.size.width, f.size.height-48) style:UITableViewStylePlain];
        _table.backgroundColor = UIColor.clearColor; _table.dataSource = self; _table.delegate = self;
        _table.separatorStyle = UITableViewCellSeparatorStyleNone; _table.rowHeight = 96;
        _table.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:_table];
    }
    return self;
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [LSWDescriptor all].count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    for (UIView *v in [c.contentView.subviews copy]) [v removeFromSuperview];
    c.backgroundColor = UIColor.clearColor; c.selectionStyle = UITableViewCellSelectionStyleNone;
    LSWDescriptor *d = [LSWDescriptor all][ip.row];
    LSWWidgetView *w = [d makeView];
    w.center = CGPointMake(24 + w.bounds.size.width/2, 48);
    w.userInteractionEnabled = NO;
    [c.contentView addSubview:w];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(24 + w.bounds.size.width + 16, 36, 200, 24)];
    l.text = d.title; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [c.contentView addSubview:l];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (self.onPick) self.onPick([LSWDescriptor all][ip.row].identifier);
}
@end

#pragma mark - Block

@interface LSWBlockView ()
@property (nonatomic, strong) NSMutableArray<LSWWidgetView *> *widgetViews;
@property (nonatomic, strong) UIButton *addButton;      // "+ ADD WIDGETS" (edit mode, empty/with room)
@property (nonatomic, strong) UIView *handle;           // drag the whole block
@property (nonatomic, strong) UIView *border;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) LSWPicker *picker;
@property (nonatomic, strong) UIButton *doneButton;
@end

@implementation LSWBlockView

static const CGFloat kSlot = 64, kGap = 12;

- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        _widgetViews = [NSMutableArray array];
        _border = [UIView new]; _border.layer.cornerRadius = 22; _border.layer.borderWidth = 1.5;
        _border.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor; _border.hidden = YES;
        _border.userInteractionEnabled = NO; [self addSubview:_border];
        _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_addButton setTitle:@"＋ ADD WIDGETS" forState:UIControlStateNormal];
        _addButton.tintColor = UIColor.whiteColor; _addButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_addButton addTarget:self action:@selector(showPicker) forControlEvents:UIControlEventTouchUpInside];
        _addButton.hidden = YES; [self addSubview:_addButton];
        _handle = [UIView new]; _handle.backgroundColor = [UIColor colorWithWhite:1 alpha:0.7];
        _handle.layer.cornerRadius = 3; _handle.hidden = YES;
        [self addSubview:_handle];
        [_handle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBlock:)]];
        // generous touch area for the handle
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    }
    return self;
}
- (void)tick { for (LSWWidgetView *w in self.widgetViews) [w update]; }

- (NSArray<NSString *> *)idents { return [[LSWManager shared] prefForKey:kWidgets default:@[@"battery", @"calendar"]]; }

- (void)reloadFromPrefs {
    LSWManager *m = [LSWManager shared];
    for (LSWWidgetView *w in self.widgetViews) [w removeFromSuperview];
    [self.widgetViews removeAllObjects];
    NSInteger maxRows = [[m prefForKey:@"maxRows" default:@2] integerValue];
    CGFloat scale = [[m prefForKey:@"scale" default:@1.0] doubleValue];
    NSInteger col = 0, row = 0;
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *ident in [self idents]) {
        LSWDescriptor *d = [LSWDescriptor descriptorForIdentifier:ident];
        if (!d) continue;
        if (col + d.slots > 4) { col = 0; row++; }
        if (row >= maxRows) break;
        LSWWidgetView *w = [d makeView];
        w.frame = CGRectMake(col*(kSlot+kGap), row*(kSlot+kGap), d.slots*kSlot + (d.slots-1)*kGap, kSlot);
        [self addSubview:w]; [self.widgetViews addObject:w]; [kept addObject:ident];
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragWidget:)];
        p.enabled = self.editing; [w addGestureRecognizer:p];
        col += d.slots;
    }
    NSInteger rowsUsed = MAX(1, row + (col>0 ? 1 : 0));
    CGFloat w = 4*kSlot + 3*kGap, h = rowsUsed*kSlot + (rowsUsed-1)*kGap;
    CGFloat pad = 12;
    CGRect screen = self.superview.bounds;
    CGFloat bw = w + 2*pad, bh = h + 2*pad;
    BOOL lockX = [[m prefForKey:@"lockX" default:@YES] boolValue];
    CGFloat x = lockX ? (screen.size.width - bw*scale)/2
                      : (screen.size.width - bw*scale)/2 + [[m prefForKey:@"blockX" default:@0] doubleValue];
    CGFloat y = [[m prefForKey:@"blockY" default:@(screen.size.height - 260)] doubleValue];
    // widgets live inside with padding
    for (LSWWidgetView *v in self.widgetViews) v.frame = CGRectOffset(v.frame, pad, pad);
    self.bounds = CGRectMake(0, 0, bw, bh);
    self.transform = CGAffineTransformMakeScale(scale, scale);
    self.frame = CGRectMake(x, y, bw*scale, bh*scale);
    self.border.frame = self.bounds;
    self.addButton.frame = self.bounds;
    self.addButton.hidden = !(self.editing && self.widgetViews.count == 0);
    self.handle.frame = CGRectMake(bw/2 - 30, bh + 6, 60, 6);
    for (LSWWidgetView *v in self.widgetViews) [v update];
    if (kept.count != [self idents].count) [m setPref:kept forKey:kWidgets];
    self.hidden = ![[m prefForKey:@"enabled" default:@YES] boolValue];
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    // widgets always tappable; handle (edit mode) gets a bigger target
    CGRect big = CGRectInset(self.handle.frame, -30, -22);
    return [super pointInside:p withEvent:e] || (self.editing && CGRectContainsPoint(big, p));
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.editing && CGRectContainsPoint(CGRectInset(self.handle.frame, -30, -22), p)) return self.handle;
    return [super hitTest:p withEvent:e];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    if (_editing == editing) return;
    _editing = editing;
    [self reloadFromPrefs];
    for (LSWWidgetView *w in self.widgetViews) for (UIGestureRecognizer *g in w.gestureRecognizers) g.enabled = editing;
    void (^apply)(void) = ^{
        self.border.hidden = !editing; self.handle.hidden = !editing;
        self.addButton.hidden = !(editing && self.widgetViews.count == 0);
    };
    if (animated) [UIView transitionWithView:self duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:apply completion:nil];
    else apply();
    [self.superview viewWithTag:7726].hidden = !editing;      // mini window
    if (!editing) [self hidePicker];
    [self bringMiniWindow];
}

#pragma mark mini window ("+ Add Widgets" bar shown in edit mode)

- (void)bringMiniWindow {
    UIView *host = self.superview;
    UIView *bar = [host viewWithTag:7726];
    if (self.editing && !bar) {
        bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 44)];
        bar.tag = 7726;
        UIVisualEffectView *b = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        b.frame = bar.bounds; b.layer.cornerRadius = 22; b.clipsToBounds = YES; [bar addSubview:b];
        UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem]; add.frame = CGRectMake(0, 0, 130, 44);
        [add setTitle:@"＋ Add Widgets" forState:UIControlStateNormal]; add.tintColor = UIColor.whiteColor;
        [add addTarget:self action:@selector(showPicker) forControlEvents:UIControlEventTouchUpInside];
        UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem]; done.frame = CGRectMake(130, 0, 90, 44);
        [done setTitle:@"Done" forState:UIControlStateNormal]; done.tintColor = UIColor.whiteColor;
        done.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        [done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:add]; [bar addSubview:done];
        [host addSubview:bar];
    }
    bar.center = CGPointMake(host.bounds.size.width/2, 90);
    [host bringSubviewToFront:bar]; [host bringSubviewToFront:self];
    bar.hidden = !self.editing;
}
- (void)doneTapped { [self setEditing:NO animated:YES]; }

#pragma mark picker

- (void)showPicker {
    if (self.picker) return;
    UIView *host = self.superview; CGFloat h = host.bounds.size.height * 0.62;
    self.picker = [[LSWPicker alloc] initWithFrame:CGRectMake(12, host.bounds.size.height, host.bounds.size.width-24, h)];
    __weak typeof(self) ws = self;
    self.picker.onPick = ^(NSString *ident) {
        LSWManager *m = [LSWManager shared];
        NSMutableArray *a = [[ws idents] mutableCopy]; [a addObject:ident];
        [m setPref:a forKey:kWidgets];
        [ws reloadFromPrefs];              // applied immediately - no respring
        [ws hidePicker];
    };
    [host addSubview:self.picker];
    [UIView animateWithDuration:0.3 animations:^{ self.picker.frame = CGRectOffset(self.picker.frame, 0, -h-12); }];
}
- (void)hidePicker {
    LSWPicker *p = self.picker; self.picker = nil; if (!p) return;
    [UIView animateWithDuration:0.25 animations:^{ p.frame = CGRectOffset(p.frame, 0, p.bounds.size.height+24); }
                     completion:^(BOOL f){ [p removeFromSuperview]; }];
}

#pragma mark dragging

- (void)dragBlock:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview]; [g setTranslation:CGPointZero inView:self.superview];
    CGRect f = self.frame; f.origin.y += t.y;
    BOOL lockX = [[[LSWManager shared] prefForKey:@"lockX" default:@YES] boolValue];
    if (!lockX) f.origin.x += t.x;
    self.frame = f;
    if (g.state == UIGestureRecognizerStateEnded) {
        LSWManager *m = [LSWManager shared];
        [m setPref:@(f.origin.y) forKey:@"blockY"];
        if (!lockX) [m setPref:@(f.origin.x - (self.superview.bounds.size.width - f.size.width)/2) forKey:@"blockX"];
    }
}

- (void)dragWidget:(UIPanGestureRecognizer *)g {
    LSWWidgetView *w = (LSWWidgetView *)g.view;
    if (g.state == UIGestureRecognizerStateBegan) { [self bringSubviewToFront:w]; [UIView animateWithDuration:.15 animations:^{ w.transform = CGAffineTransformMakeScale(1.1,1.1); }]; }
    CGPoint t = [g translationInView:self]; [g setTranslation:CGPointZero inView:self];
    w.center = CGPointMake(w.center.x + t.x, w.center.y + t.y);
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        // find insertion index by x/y proximity to other widgets' centers
        NSMutableArray *order = [NSMutableArray array];
        for (LSWWidgetView *o in self.widgetViews) if (o != w) [order addObject:o];
        NSUInteger idx = 0;
        for (LSWWidgetView *o in order) {
            BOOL before = (w.center.y > CGRectGetMaxY(o.frame)) || (fabs(w.center.y - o.center.y) < kSlot/2 && w.center.x > o.center.x);
            if (before) idx++; else break;
        }
        [order insertObject:w atIndex:MIN(idx, order.count)];
        NSMutableArray *ids = [NSMutableArray array];
        for (LSWWidgetView *o in order) [ids addObject:o.widgetIdentifier];
        [[LSWManager shared] setPref:ids forKey:kWidgets];
        w.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:.25 animations:^{ [self reloadFromPrefs]; }];
    }
}
@end

#pragma mark - Manager

@interface LSWManager () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) LSWBlockView *block;
@property (nonatomic, weak) UIView *host;
@end

#import <dlfcn.h>
static int LSWLockState(void) {
    static int (*fn)(CFDictionaryRef);
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag", RTLD_LAZY);
        if (h) fn = dlsym(h, "MKBGetDeviceLockState");
    });
    return fn ? fn(NULL) : 0;
}

@implementation LSWManager
+ (instancetype)shared { static LSWManager *m; static dispatch_once_t o; dispatch_once(&o, ^{ m = [LSWManager new]; }); return m; }

- (id)prefForKey:(NSString *)k default:(id)d {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LSW_DOMAIN);
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)LSW_DOMAIN);
    return v ?: d;
}
- (void)setPref:(id)v forKey:(NSString *)k {
    CFPreferencesSetAppValue((__bridge CFStringRef)k, (__bridge CFPropertyListRef)v, (__bridge CFStringRef)LSW_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LSW_DOMAIN);
}

- (void)attachToHostView:(UIView *)host {
    if (self.block.superview == host) return;
    self.host = host;
    if (!self.block) self.block = [LSWBlockView new];
    [host addSubview:self.block];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    lp.minimumPressDuration = [[self prefForKey:@"holdTime" default:@0.7] doubleValue];
    lp.cancelsTouchesInView = NO; lp.delegate = self;
    [host addGestureRecognizer:lp];
    [self reload];
}
- (void)bringToFront { if (self.host && self.block) { [self.host bringSubviewToFront:self.block]; [self.block bringMiniWindow]; } }
- (void)reload { [self.block reloadFromPrefs]; }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (![[self prefForKey:@"enabled" default:@YES] boolValue]) return;
    // only when the phone is unlocked (lock screen shown after Face ID / unlocked state)
    BOOL allowLocked = [[self prefForKey:@"editWhileLocked" default:@NO] boolValue];
    BOOL unlocked = (MKBGetDeviceLockState(NULL) == 0);
    if (!unlocked && !allowLocked) return;
    // ignore presses on quick-action buttons area (bottom corners)
    CGPoint p = [g locationInView:self.host];
    if (p.y > self.host.bounds.size.height - 150 && (p.x < 120 || p.x > self.host.bounds.size.width - 120)) return;
    [self.block setEditing:YES animated:YES];
}
@end
