// Rutube native UI modification for iOS. No extra playback features.
// The underlying Rutube controllers, account, player and network logic remain untouched.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface RTUIFix : NSObject
@property (nonatomic,strong) UIView *header;
@property (nonatomic,strong) UIView *footer;
@property (nonatomic,strong) UIView *subscriptions;
@property (nonatomic,strong) UIWindow *window;
@property (nonatomic,strong) NSArray<UIView *> *nativeTabs;
@property (nonatomic,strong) UIControl *searchControl;
@property (nonatomic,strong) UIControl *notificationControl;
@property (nonatomic,strong) UIControl *profileControl;
@property (nonatomic,strong) NSArray<UIBarButtonItem *> *rightNavItems;
@property (nonatomic,assign) NSInteger currentTab;
@property (nonatomic,assign) BOOL scheduled;
+ (instancetype)shared;
- (void)schedule;
- (void)refresh;
@end

static void (*OriginalViewDidAppear)(UIViewController *,SEL,BOOL);
static void RTViewDidAppear(UIViewController *vc, SEL sel, BOOL animated) {
    if (OriginalViewDidAppear) OriginalViewDidAppear(vc,sel,animated);
    [[RTUIFix shared] schedule];
}

__attribute__((constructor)) static void RTBootstrap(void) {
    Method m=class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:));
    if (m) OriginalViewDidAppear=(void *)method_setImplementation(m,(IMP)RTViewDidAppear);
    dispatch_async(dispatch_get_main_queue(),^{ [[RTUIFix shared] schedule]; });
}

@implementation RTUIFix
+ (instancetype)shared {
    static RTUIFix *value;
    static dispatch_once_t once;
    dispatch_once(&once,^{ value=[RTUIFix new]; value.currentTab=0; });
    return value;
}
- (void)schedule {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(),^{[self schedule];}); return; }
    if (self.scheduled) return;
    self.scheduled=YES;
    dispatch_async(dispatch_get_main_queue(),^{self.scheduled=NO; [self refresh];});
}
- (void)walk:(UIView *)view with:(void(^)(UIView *))visit {
    if (!view) return;
    visit(view);
    for (UIView *child in [view.subviews copy]) [self walk:child with:visit];
}
- (UIWindow *)mainWindow {
    UIWindow *win=UIApplication.sharedApplication.keyWindow;
    if (win && !win.hidden) return win;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.hidden && w.windowLevel==UIWindowLevelNormal) return w;
    return nil;
}
- (UIControl *)firstControl:(UIView *)view {
    if ([view isKindOfClass:UIControl.class]) return (UIControl *)view;
    for (UIView *v in view.subviews) {
        UIControl *c=[self firstControl:v];
        if (c) return c;
    }
    return nil;
}
- (void)activate:(NSInteger)idx {
    if (idx<0 || idx>=self.nativeTabs.count) return;
    UIControl *ctl=[self firstControl:self.nativeTabs[idx]];
    if (ctl) [ctl sendActionsForControlEvents:UIControlEventTouchUpInside];
    else {
        UITabBarController *tab=[self findTab:self.window.rootViewController];
        if (tab && idx<tab.viewControllers.count) tab.selectedIndex=idx;
        else NSLog(@"[RTUIFix] Original tab %ld has no UIKit control", (long)idx);
    }
    self.currentTab=idx;
    [self schedule];
}
- (UITabBarController *)findTab:(UIViewController *)vc {
    if ([vc isKindOfClass:UITabBarController.class]) return (UITabBarController *)vc;
    for (UIViewController *child in vc.childViewControllers) {
        UITabBarController *result=[self findTab:child];
        if (result) return result;
    }
    return nil;
}
- (void)activateBarItem:(UIBarButtonItem *)item {
    if (item.target && item.action)
        [UIApplication.sharedApplication sendAction:item.action to:item.target from:item forEvent:nil];
    else if (item.customView) [[self firstControl:item.customView] sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)tapSearch {
    if (self.searchControl) [self.searchControl sendActionsForControlEvents:UIControlEventTouchUpInside];
    else if (self.rightNavItems.count>=4) [self activateBarItem:self.rightNavItems[1]];
    else NSLog(@"[RTUIFix] No original search action found");
    [self schedule];
}
- (void)tapNotifications {
    if (self.notificationControl) [self.notificationControl sendActionsForControlEvents:UIControlEventTouchUpInside];
    else if (self.rightNavItems.count>=4) [self activateBarItem:self.rightNavItems[2]];
    else NSLog(@"[RTUIFix] No original notifications action found");
    [self schedule];
}
- (void)tapProfile {
    if (self.profileControl) [self.profileControl sendActionsForControlEvents:UIControlEventTouchUpInside];
    else if (self.rightNavItems.count>=4) [self activateBarItem:self.rightNavItems[0]];
    else [self activate:4];
}
- (void)tapHome { [self activate:0]; }
- (void)tapUpload { [self activate:2]; }
- (void)tapMine { [self activate:4]; }
- (void)tapSubscriptions { [self activate:3]; }
- (UIButton *)button:(NSString *)icon text:(NSString *)label action:(SEL)action frame:(CGRect)frame active:(BOOL)active {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=frame;
    b.accessibilityLabel=label;
    b.tintColor=active?[UIColor colorWithRed:0 green:0.71 blue:1 alpha:1]:UIColor.whiteColor;
    UIImageSymbolConfiguration *cfg=[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *img=[UIImage systemImageNamed:icon withConfiguration:cfg];
    [b setImage:img forState:UIControlStateNormal];
    b.imageView.contentMode=UIViewContentModeScaleAspectFit;
    b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentCenter;
    if (label) {
        UILabel *caption=[[UILabel alloc] initWithFrame:CGRectMake(0,44,frame.size.width,16)];
        caption.text=label;
        caption.font=[UIFont systemFontOfSize:10.5];
        caption.textColor=b.tintColor;
        caption.textAlignment=NSTextAlignmentCenter;
        [b addSubview:caption];
    }
    if (label) b.contentEdgeInsets=UIEdgeInsetsMake(0,0,20,0);
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIView *)findNativeBottom:(UIWindow *)w {
    __block UIView *bar=nil;
    [self walk:w with:^(UIView *v) {
        NSString *name=NSStringFromClass(v.class);
        if (([name hasSuffix:@".RutubeTabBar"] || [name isEqualToString:@"RutubeTabBar"]) && !v.hidden && v.alpha>0.1) {
            CGRect r=[v convertRect:v.bounds toView:w];
            if (r.origin.y>w.bounds.size.height/2 && r.size.height>=45 && r.size.width>w.bounds.size.width*0.7)
                bar=v;
        }
    }];
    return bar;
}
- (void)captureNativeTabs:(UIView *)bar {
    NSMutableArray<UIView *> *tabs=[NSMutableArray array];
    [self walk:bar with:^(UIView *v) {
        NSString *name=NSStringFromClass(v.class);
        if ([name hasSuffix:@".RutubeTabBarItemView"] || [name isEqualToString:@"RutubeTabBarItemView"])
            [tabs addObject:v];
    }];
    [tabs sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b) {
        CGFloat x=CGRectGetMidX([a convertRect:a.bounds toView:self.window]);
        CGFloat y=CGRectGetMidX([b convertRect:b.bounds toView:self.window]);
        return x<y?NSOrderedAscending:(x>y?NSOrderedDescending:NSOrderedSame);
    }];
    self.nativeTabs=tabs;
}
- (void)captureOriginalHeader {
    self.searchControl=nil;
    self.notificationControl=nil;
    self.profileControl=nil;
    __block UINavigationBar *nav=nil;
    [self walk:self.window with:^(UIView *v) {
        if (self.header && [v isDescendantOfView:self.header]) return;
        if (self.footer && [v isDescendantOfView:self.footer]) return;
        CGRect r=[v convertRect:v.bounds toView:self.window];
        if ([v isKindOfClass:UINavigationBar.class] && r.origin.y<180 && r.size.width>200) nav=(UINavigationBar *)v;
        if (![v isKindOfClass:UIControl.class] || v.hidden || v.alpha<0.1 || r.origin.y>self.window.safeAreaInsets.top+125) return;
        NSString *s=[NSString stringWithFormat:@"%@ %@",v.accessibilityLabel?:@"",v.accessibilityIdentifier?:@""].lowercaseString;
        if (([s containsString:@"search"] || [s containsString:@"поиск"]) && !self.searchControl) self.searchControl=(UIControl *)v;
        if (([s containsString:@"notification"] || [s containsString:@"уведом"]) && !self.notificationControl) self.notificationControl=(UIControl *)v;
        if (([s containsString:@"profile"] || [s containsString:@"account"] || [s containsString:@"профил"]) && !self.profileControl) self.profileControl=(UIControl *)v;
    }];
    self.rightNavItems=nav.topItem.rightBarButtonItems;
}
- (void)drawHeader {
    UIWindow *w=self.window;
    CGRect r=CGRectMake(0,w.safeAreaInsets.top,w.bounds.size.width,56);
    if (!self.header) {
        self.header=[[UIView alloc] init];
        self.header.backgroundColor=[UIColor colorWithRed:0.073 green:0.086 blue:0.107 alpha:1];
    }
    self.header.frame=r;
    for (UIView *v in [self.header.subviews copy]) [v removeFromSuperview];
    UIButton *menu=[self button:@"line.3.horizontal" text:nil action:@selector(showMenu)
                         frame:CGRectMake(8,0,48,56) active:NO];
    [self.header addSubview:menu];
    UILabel *logo=[[UILabel alloc] initWithFrame:CGRectMake(69,0,w.bounds.size.width-148,56)];
    logo.text=@"RUTUBE"; logo.font=[UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
    logo.textColor=UIColor.whiteColor;
    [self.header addSubview:logo];
    UIButton *profile=[self button:@"person" text:nil action:@selector(tapProfile)
                           frame:CGRectMake(w.bounds.size.width-61,0,48,56) active:NO];
    [self.header addSubview:profile];
    if (self.header.superview!=w) [w addSubview:self.header];
    [w bringSubviewToFront:self.header];
}
- (void)showMenu {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"Rutube" message:nil
                                                 preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Подписки" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[self tapSubscriptions];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Моё" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[self tapMine];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *vc=self.window.rootViewController;
    while (vc.presentedViewController) vc=vc.presentedViewController;
    UIPopoverPresentationController *pop=menu.popoverPresentationController;
    if (pop) {pop.sourceView=self.header; pop.sourceRect=CGRectMake(18,18,30,30);}
    [vc presentViewController:menu animated:YES completion:nil];
}
- (void)drawFooter:(UIView *)native {
    UIWindow *w=self.window;
    CGRect r=[native convertRect:native.bounds toView:w];
    if (r.size.height<48 || r.size.height>170) return;
    if (!self.footer) {
        self.footer=[[UIView alloc] init];
        self.footer.backgroundColor=[UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1];
    }
    self.footer.frame=r;
    for (UIView *v in [self.footer.subviews copy]) [v removeFromSuperview];
    NSArray *titles=@[@"Главная",@"Поиск",@"Загрузить",@"Уведомления",@"Моё"];
    NSArray *icons=@[@"house",@"magnifyingglass",@"plus.circle",@"bell",@"person.crop.circle"];
    SEL actions[]={@selector(tapHome),@selector(tapSearch),@selector(tapUpload),
                    @selector(tapNotifications),@selector(tapMine)};
    CGFloat cw=r.size.width/5;
    for (NSInteger i=0;i<5;i++) {
        BOOL active=(self.currentTab==(i==0?0:(i==2?2:(i==4?4:-100))));
        UIButton *button=[self button:icons[i] text:titles[i] action:actions[i]
                    frame:CGRectMake(cw*i,0,cw,MIN(r.size.height,70)) active:active];
        [self.footer addSubview:button];
    }
    if (self.footer.superview!=w) [w addSubview:self.footer];
    [w bringSubviewToFront:self.footer];
}
- (void)drawSubscriptions {
    if (self.currentTab!=4) { self.subscriptions.hidden=YES; return; }
    UIWindow *w=self.window;
    if (!self.subscriptions) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"Подписки на каналы ›" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        button.backgroundColor=[UIColor colorWithWhite:0.16 alpha:1];
        button.layer.cornerRadius=12;
        [button addTarget:self action:@selector(tapSubscriptions) forControlEvents:UIControlEventTouchUpInside];
        self.subscriptions=button;
    }
    self.subscriptions.frame=CGRectMake(16,w.safeAreaInsets.top+64,w.bounds.size.width-32,50);
    self.subscriptions.hidden=NO;
    if (self.subscriptions.superview!=w) [w addSubview:self.subscriptions];
    [w bringSubviewToFront:self.subscriptions];
}
- (void)refresh {
    UIWindow *win=[self mainWindow];
    if (!win) return;
    self.window=win;
    UIView *native=[self findNativeBottom:win];
    if (!native) {
        self.header.hidden=YES;
        self.footer.hidden=YES;
        self.subscriptions.hidden=YES;
        return;
    }
    [self captureNativeTabs:native];
    if (self.nativeTabs.count<5) {
        self.header.hidden=YES;
        self.footer.hidden=YES;
        self.subscriptions.hidden=YES;
        return;
    }
    [self captureOriginalHeader];
    [self drawHeader];
    [self drawFooter:native];
    [self drawSubscriptions];
    self.header.hidden=NO;
    self.footer.hidden=NO;
}
@end
