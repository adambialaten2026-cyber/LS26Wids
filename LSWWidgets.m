#import "LSW.h"
#import <EventKit/EventKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static UIColor *LSWFg(void) { return UIColor.whiteColor; }
static UIView *LSWBubble(CGRect f) {
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    v.frame = f; v.layer.cornerRadius = MIN(f.size.width, f.size.height)/2 > 32 ? 22 : f.size.height/2;
    v.clipsToBounds = YES; return v;
}
static UILabel *LSWLabel(NSString *t, CGFloat sz, UIFontWeight w, CGRect f, NSTextAlignment a) {
    UILabel *l = [[UILabel alloc] initWithFrame:f]; l.text = t; l.textColor = LSWFg();
    l.font = [UIFont systemFontOfSize:sz weight:w]; l.textAlignment = a; l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = .6; return l;
}
static EKEventStore *LSWStore(void) {
    static EKEventStore *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [EKEventStore new];
        [s requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL g, NSError *e){}];
        [s requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL g, NSError *e){}]; });
    return s;
}

@interface LSWWidgetView ()
@property (nonatomic, copy) NSString *widgetIdentifier;
@property (nonatomic, strong) NSMutableArray<UILabel *> *labels;
@property (nonatomic, strong) CAShapeLayer *ring;
@end

@implementation LSWWidgetView
- (instancetype)initWithIdentifier:(NSString *)ident {
    LSWDescriptor *d = [LSWDescriptor descriptorForIdentifier:ident];
    CGFloat w = d.slots*64 + (d.slots-1)*12;
    if ((self = [super initWithFrame:CGRectMake(0,0,w,64)])) {
        _widgetIdentifier = ident; _labels = [NSMutableArray array];
        [self addSubview:LSWBubble(self.bounds)];
        [self build];
    }
    return self;
}
- (UILabel *)addLabel:(NSString *)t size:(CGFloat)s weight:(UIFontWeight)w frame:(CGRect)f align:(NSTextAlignment)a {
    UILabel *l = LSWLabel(t, s, w, f, a); [self addSubview:l]; [self.labels addObject:l]; return l;
}
- (void)addRingWithProgress:(CGFloat)p {
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(32,32) radius:27 startAngle:-M_PI_2 endAngle:M_PI*1.5 clockwise:YES];
    CAShapeLayer *bg = [CAShapeLayer layer]; bg.path = path.CGPath; bg.fillColor = nil; bg.strokeColor = [UIColor colorWithWhite:1 alpha:.25].CGColor; bg.lineWidth = 5;
    [self.layer addSublayer:bg];
    _ring = [CAShapeLayer layer]; _ring.path = path.CGPath; _ring.fillColor = nil; _ring.strokeColor = UIColor.whiteColor.CGColor;
    _ring.lineWidth = 5; _ring.lineCap = kCALineCapRound; _ring.strokeEnd = p; [self.layer addSublayer:_ring];
}

- (void)build {
    NSString *i = self.widgetIdentifier;
    if ([i isEqualToString:@"battery"]) {
        [self addRingWithProgress:0]; [self addLabel:@"--" size:17 weight:UIFontWeightBold frame:CGRectMake(8,20,48,24) align:NSTextAlignmentCenter];
    } else if ([i isEqualToString:@"digitalclock"]) {
        [self addLabel:@"--:--" size:20 weight:UIFontWeightBold frame:CGRectMake(4,16,56,22) align:NSTextAlignmentCenter];
        [self addLabel:@"" size:11 weight:UIFontWeightMedium frame:CGRectMake(4,38,56,14) align:NSTextAlignmentCenter];
    } else if ([i isEqualToString:@"worldclock"]) {
        for (int k=0;k<3;k++) [self addLabel:@"" size:12 weight:UIFontWeightSemibold frame:CGRectMake(12,8+k*17,self.bounds.size.width-24,16) align:NSTextAlignmentLeft];
    } else if ([i isEqualToString:@"calendar"] || [i isEqualToString:@"reminders"] || [i isEqualToString:@"weather"]) {
        [self addLabel:@"" size:12 weight:UIFontWeightSemibold frame:CGRectMake(14,8,self.bounds.size.width-28,16) align:NSTextAlignmentLeft];
        [self addLabel:@"" size:15 weight:UIFontWeightBold frame:CGRectMake(14,24,self.bounds.size.width-28,20) align:NSTextAlignmentLeft];
        [self addLabel:@"" size:12 weight:UIFontWeightRegular frame:CGRectMake(14,44,self.bounds.size.width-28,14) align:NSTextAlignmentLeft];
    } else if ([i isEqualToString:@"temperature"]) {
        [self addLabel:@"--°" size:20 weight:UIFontWeightBold frame:CGRectMake(4,14,56,24) align:NSTextAlignmentCenter];
        [self addLabel:@"" size:10 weight:UIFontWeightMedium frame:CGRectMake(4,38,56,14) align:NSTextAlignmentCenter];
    }
}

// best-effort local weather from Weather.framework (private, iOS 15) -> {temp, cond, hi, lo}
+ (NSDictionary *)weather {
    static BOOL loaded; if (!loaded) { dlopen("/System/Library/PrivateFrameworks/Weather.framework/Weather", RTLD_LAZY); loaded = YES; }
    @try {
        Class WP = NSClassFromString(@"WeatherPreferences"); id prefs = [WP performSelector:NSSelectorFromString(@"sharedPreferences")];
        id city = [prefs performSelector:NSSelectorFromString(@"localWeatherCity")];
        if (!city) { NSArray *c = [prefs performSelector:NSSelectorFromString(@"loadSavedCities")]; city = c.firstObject; }
        if (!city) return nil;
        id t = [city valueForKey:@"temperature"];
        double c = [t respondsToSelector:@selector(doubleValue)] ? [t doubleValue] : [[t valueForKey:@"celsius"] doubleValue];
        NSString *cond = [city respondsToSelector:NSSelectorFromString(@"conditionDescription")] ? [city valueForKey:@"conditionDescription"] : @"";
        return @{@"temp":@(c), @"cond":cond ?: @""};
    } @catch (__unused id e) { return nil; }
}

- (void)update {
    NSString *i = self.widgetIdentifier;
    if ([i isEqualToString:@"battery"]) {
        UIDevice.currentDevice.batteryMonitoringEnabled = YES; float l = UIDevice.currentDevice.batteryLevel;
        self.ring.strokeEnd = MAX(l,0); self.labels[0].text = l < 0 ? @"--" : [NSString stringWithFormat:@"%d%%", (int)roundf(l*100)];
    } else if ([i isEqualToString:@"digitalclock"]) {
        NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm"; self.labels[0].text = [f stringFromDate:NSDate.date];
        f.dateFormat = @"EEE d"; self.labels[1].text = [f stringFromDate:NSDate.date];
    } else if ([i isEqualToString:@"worldclock"]) {
        NSArray *zones = @[@[@"CUP",@"America/Los_Angeles"], @[@"LON",@"Europe/London"], @[@"TOK",@"Asia/Tokyo"]];
        NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"H:mm";
        for (int k=0;k<3;k++) { f.timeZone = [NSTimeZone timeZoneWithName:zones[k][1]];
            self.labels[k].text = [NSString stringWithFormat:@"%@   %@", zones[k][0], [f stringFromDate:NSDate.date]]; }
    } else if ([i isEqualToString:@"calendar"]) {
        self.labels[0].text = @"CALENDAR"; self.labels[1].text = @"No events today"; self.labels[2].text = @"";
        if ([EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent] == EKAuthorizationStatusAuthorized) {
            EKEventStore *s = LSWStore();
            NSPredicate *p = [s predicateForEventsWithStartDate:NSDate.date endDate:[NSDate.date dateByAddingTimeInterval:86400] calendars:nil];
            NSArray *evs = [[s eventsMatchingPredicate:p] sortedArrayUsingComparator:^NSComparisonResult(EKEvent *a, EKEvent *b){ return [a.startDate compare:b.startDate]; }];
            EKEvent *e = evs.firstObject;
            if (e) { NSDateFormatter *f = [NSDateFormatter new]; f.timeStyle = NSDateFormatterShortStyle;
                self.labels[1].text = e.title; self.labels[2].text = [f stringFromDate:e.startDate]; }
        } else { LSWStore(); self.labels[1].text = @"Calendar access needed"; }
    } else if ([i isEqualToString:@"reminders"]) {
        self.labels[0].text = @"REMINDERS"; self.labels[1].text = @"All done";
        if ([EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder] == EKAuthorizationStatusAuthorized) {
            EKEventStore *s = LSWStore(); __weak typeof(self) ws = self;
            [s fetchRemindersMatchingPredicate:[s predicateForIncompleteRemindersWithDueDateStarting:nil ending:nil calendars:nil] completion:^(NSArray *r){
                dispatch_async(dispatch_get_main_queue(), ^{ EKReminder *x = r.firstObject;
                    ws.labels[1].text = x ? x.title : @"All done";
                    ws.labels[2].text = r.count ? [NSString stringWithFormat:@"%lu pending", (unsigned long)r.count] : @""; });
            }];
        } else { LSWStore(); self.labels[1].text = @"Reminders access needed"; }
    } else if ([i isEqualToString:@"weather"] || [i isEqualToString:@"temperature"]) {
        NSDictionary *w = [LSWWidgetView weather];
        NSString *t = w ? [NSString stringWithFormat:@"%d°", (int)round([w[@"temp"] doubleValue])] : @"--°";
        if ([i isEqualToString:@"weather"]) { self.labels[0].text = @"WEATHER"; self.labels[1].text = t; self.labels[2].text = w[@"cond"] ?: @""; }
        else { self.labels[0].text = t; self.labels[1].text = w[@"cond"] ?: @""; }
    }
}
@end

@implementation LSWDescriptor
+ (NSArray<LSWDescriptor *> *)all {
    static NSArray *a; static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSArray *defs = @[ @[@"battery",@"Battery",@1], @[@"digitalclock",@"Digital Clock",@1], @[@"temperature",@"Temperature",@1],
                           @[@"weather",@"Weather Condition",@2], @[@"calendar",@"Calendar",@2], @[@"reminders",@"Reminders",@2], @[@"worldclock",@"World Clock",@2] ];
        NSMutableArray *r = [NSMutableArray array];
        for (NSArray *d in defs) { LSWDescriptor *x = [LSWDescriptor new]; x.identifier = d[0]; x.title = d[1]; x.slots = [d[2] integerValue]; [r addObject:x]; }
        a = r;
    });
    return a;
}
+ (LSWDescriptor *)descriptorForIdentifier:(NSString *)ident { for (LSWDescriptor *d in [self all]) if ([d.identifier isEqualToString:ident]) return d; return nil; }
- (LSWWidgetView *)makeView { return [[LSWWidgetView alloc] initWithIdentifier:self.identifier]; }
@end
