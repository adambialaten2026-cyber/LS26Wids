#import <UIKit/UIKit.h>

#define LSW_DOMAIN @"com.ls26wids.prefs"
#define LSW_RELOAD_NOTIF "com.ls26wids/reload"

// ---------- Widget base ----------
@interface LSWWidgetView : UIView
@property (nonatomic, readonly) NSString *widgetIdentifier;
- (instancetype)initWithIdentifier:(NSString *)ident;
- (void)update;            // refresh live data
@end

@interface LSWDescriptor : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger slots;     // 1 = circle, 2 = wide rectangle
+ (NSArray<LSWDescriptor *> *)all;
+ (LSWDescriptor *)descriptorForIdentifier:(NSString *)ident;
- (LSWWidgetView *)makeView;
@end

// ---------- Block / manager ----------
@interface LSWBlockView : UIView
@property (nonatomic, readonly) BOOL editing;
- (void)reloadFromPrefs;
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
@end

@interface LSWManager : NSObject
+ (instancetype)shared;
- (void)attachToHostView:(UIView *)host;
- (void)bringToFront;
- (void)reload;
// prefs
- (id)prefForKey:(NSString *)key default:(id)def;
- (void)setPref:(id)value forKey:(NSString *)key;
@property (nonatomic, readonly) LSWBlockView *block;
@end
