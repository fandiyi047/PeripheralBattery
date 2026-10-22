// SPDX-License-Identifier: GPL-3.0-or-later
// Protocol references and attribution: see README.md.
#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#include <unistd.h>
#include <assert.h>

typedef struct { int keyboard, mouse; BOOL keyboardCharging; } Readings;
static BOOL diagnostic=NO;
static int number(IOHIDDeviceRef d, CFStringRef key) {
    CFTypeRef v=IOHIDDeviceGetProperty(d,key); int x=0;
    if(v && CFGetTypeID(v)==CFNumberGetTypeID()) CFNumberGetValue(v,kCFNumberIntType,&x);
    return x;
}
static int parseMouse(const uint8_t *b, size_t len, uint8_t tid) {
    if(len!=90 || b[0]!=2 || b[1]!=tid || b[5]!=2 || b[6]!=7 || b[7]!=0x80) return -1;
    uint8_t crc=0; for(int i=2;i<88;i++) crc^=b[i];
    if(crc!=b[88]) return -1;
    return (b[9]*100+127)/255;
}
static int parseKeyboard(const uint8_t *b, size_t len) {
    if(len!=64 || b[0]!=2 || b[1]!=0x12 || b[2]!=1 || b[11]>100) return -1;
    return b[11];
}
static BOOL parseKeyboardCharging(const uint8_t *b, size_t len) {
    return parseKeyboard(b,len)>=0 && b[9]==1;
}
static int queryMouse(IOHIDDeviceRef d) {
    uint8_t ids[]={0x1f,0x3f};
    for(int j=0;j<2;j++) {
        uint8_t b[90]={0}; b[1]=ids[j]; b[5]=2; b[6]=7; b[7]=0x80;
        for(int i=2;i<88;i++) b[88]^=b[i];
        if(IOHIDDeviceSetReport(d,kIOHIDReportTypeFeature,0,b,90)!=kIOReturnSuccess) continue;
        usleep(30000); memset(b,0,sizeof(b)); CFIndex len=90;
        if(IOHIDDeviceGetReport(d,kIOHIDReportTypeFeature,0,b,&len)==kIOReturnSuccess) {
            int pct=parseMouse(b,len,ids[j]); if(pct>=0) return pct;
        }
    }
    return -1;
}
static void keyboardReport(void *ctx, IOReturn rc, void *sender, IOHIDReportType type,
                           uint32_t rid, uint8_t *bytes, CFIndex len) {
    if(rc==kIOReturnSuccess && type==kIOHIDReportTypeInput && rid==2) {
        int pct=parseKeyboard(bytes,len);
        if(pct>=0) { Readings *r=ctx; r->keyboard=pct; r->keyboardCharging=parseKeyboardCharging(bytes,len); }
    }
}
static void queryKeyboard(IOHIDDeviceRef d, Readings *r) {
    r->keyboard=-1; r->keyboardCharging=NO; uint8_t input[64]={0}, output[64]={2,0x12,1};
    CFRunLoopRef loop=CFRunLoopGetCurrent();
    IOHIDDeviceRegisterInputReportCallback(d,input,sizeof(input),keyboardReport,r);
    IOHIDDeviceScheduleWithRunLoop(d,loop,kCFRunLoopDefaultMode);
    if(IOHIDDeviceSetReport(d,kIOHIDReportTypeOutput,2,output,sizeof(output))==kIOReturnSuccess) {
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+0.5;
        while(r->keyboard<0 && CFAbsoluteTimeGetCurrent()<deadline)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.05,true);
    }
    IOHIDDeviceUnscheduleFromRunLoop(d,loop,kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(d,input,sizeof(input),NULL,NULL);
}
static Readings query(void) {
    Readings r={-1,-1};
    IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    NSArray *matches=@[
        @{@kIOHIDVendorIDKey:@0x1532,@kIOHIDProductIDKey:@0x00b8},
        @{@kIOHIDVendorIDKey:@0x0b05,@kIOHIDProductIDKey:@0x1ace}
    ];
    IOHIDManagerSetDeviceMatchingMultiple(manager,(__bridge CFArrayRef)matches);
    CFSetRef devices=IOHIDManagerCopyDevices(manager);
    for(id obj in (__bridge NSSet*)devices) {
        IOHIDDeviceRef d=(__bridge IOHIDDeviceRef)obj;
        BOOL mouse=number(d,CFSTR(kIOHIDVendorIDKey))==0x1532 && number(d,CFSTR(kIOHIDMaxFeatureReportSizeKey))==90;
        BOOL keyboard=number(d,CFSTR(kIOHIDVendorIDKey))==0x0b05 && number(d,CFSTR(kIOHIDPrimaryUsagePageKey))==0xff02;
        if(!mouse && !keyboard) continue;
        // Shared access only; never seize keyboard/mouse input from macOS.
        IOReturn opened=IOHIDDeviceOpen(d,kIOHIDOptionsTypeNone);
        if(diagnostic) fprintf(stderr,"%s open: 0x%x\n",mouse?"mouse":"keyboard",opened);
        if(opened!=kIOReturnSuccess) {
            if(mouse && opened==kIOReturnNotPermitted) r.mouse=-2;
            continue;
        }
        if(mouse) r.mouse=queryMouse(d); else queryKeyboard(d,&r);
        if(opened==kIOReturnSuccess) IOHIDDeviceClose(d,kIOHIDOptionsTypeNone);
    }
    if(devices) CFRelease(devices);
    CFRelease(manager);
    return r;
}
static NSString *percent(int n) { return n==-2?@"!":n<0?@"—":[NSString stringWithFormat:@"%d%%",n]; }

static NSImage *symbol(NSString *name, CGFloat size) {
    return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular]];
}
@interface BatteryCard : NSView
@property int keyboard;
@property int mouse;
@property BOOL keyboardCharging;
@end
@implementation BatteryCard
- (BOOL)isOpaque { return NO; }
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)dirty {
    [@"外设电量" drawAtPoint:NSMakePoint(18,10) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
    NSArray *titles=@[@"ROG Falchion RX",@"Razer Viper V3"];
    NSArray *icons=@[@"keyboard",@"computermouse"];
    int vals[]={self.keyboard,self.mouse};
    for(int i=0;i<2;i++) {
        CGFloat y=32+i*56;
        // Leave the row transparent; NSMenu supplies the system material.
        // Custom-drawn menu views do not automatically tint template symbols.
        // Resolve labelColor in this view's current appearance on each redraw.
        NSImage *im=symbol(icons[i],32);
        NSImage *tinted=[NSImage imageWithSize:NSMakeSize(34,34) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            CGFloat scale=MIN(rect.size.width/im.size.width,rect.size.height/im.size.height);
            NSSize size=NSMakeSize(im.size.width*scale,im.size.height*scale);
            NSRect fit=NSMakeRect((rect.size.width-size.width)/2,(rect.size.height-size.height)/2,size.width,size.height);
            [im drawInRect:fit fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
            [NSColor.labelColor setFill];
            NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn);
            return YES;
        }];
        [tinted drawInRect:NSMakeRect(15,y+5,34,34) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        [titles[i] drawAtPoint:NSMakePoint(60,y+8) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.labelColor}];
        NSString *pct=percent(vals[i]);
        NSDictionary *attrs=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.labelColor};
        CGFloat percentX=278-[pct sizeWithAttributes:attrs].width;
        [pct drawAtPoint:NSMakePoint(percentX,y+8) withAttributes:attrs];
        if(i==0 && self.keyboardCharging && vals[i]>=0) {
            NSImage *bolt=symbol(@"bolt",11);
            NSImage *chargingIcon=[NSImage imageWithSize:NSMakeSize(9,13) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                CGFloat scale=MIN(rect.size.width/bolt.size.width,rect.size.height/bolt.size.height);
                NSSize size=NSMakeSize(bolt.size.width*scale,bolt.size.height*scale);
                NSRect fit=NSMakeRect((rect.size.width-size.width)/2,(rect.size.height-size.height)/2,size.width,size.height);
                [bolt drawInRect:fit fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
                [NSColor.labelColor setFill];
                NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn);
                return YES;
            }];
            [chargingIcon drawInRect:NSMakeRect(percentX-14,y+10,9,13) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        }
        if(vals[i]<0) {
            [(vals[i]==-2?@"需要输入监控权限":@"休眠或未连接") drawAtPoint:NSMakePoint(60,y+29) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
        } else {
            [NSColor.quaternaryLabelColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(60,y+31,218,4) xRadius:2 yRadius:2] fill];
            [(vals[i]<=20?NSColor.systemOrangeColor:NSColor.systemGreenColor) setFill];
            if(vals[i]>0) [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(60,y+31,218*vals[i]/100.0,4) xRadius:2 yRadius:2] fill];
        }
    }
}
@end

@interface BatteryApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *status;
@property BatteryCard *card;
@property NSButton *refreshButton;
@property NSMenuItem *permissionItem;
@property NSTimer *timer;
@property BOOL busy;
@property BOOL sleeping;
@end
@implementation BatteryApp
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.status=[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.status.button.title=@"";
    NSImage *menuIcon=symbol(@"keyboard",16);
    menuIcon.template=YES;
    self.status.button.image=menuIcon;
    self.status.button.imagePosition=NSImageOnly;
    self.status.button.accessibilityLabel=@"外设电量";
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"外设电量"];
    menu.autoenablesItems=NO;
    self.card=[[BatteryCard alloc] initWithFrame:NSMakeRect(0,0,296,148)];
    self.card.keyboard=-1; self.card.mouse=-1;
    NSMenuItem *header=[NSMenuItem new]; header.view=self.card; [menu addItem:header];
    [menu addItem:NSMenuItem.separatorItem];
    // A button hosted inside a custom menu view handles its own click without
    // NSMenu performing an item action (which would end menu tracking).
    NSMenuItem *refreshItem=[NSMenuItem new];
    NSView *refreshRow=[[NSView alloc] initWithFrame:NSMakeRect(0,0,296,32)];
    self.refreshButton=[NSButton buttonWithTitle:@"刷新" target:self action:@selector(refresh)];
    self.refreshButton.frame=NSMakeRect(18,3,122,26);
    self.refreshButton.bordered=NO;
    self.refreshButton.alignment=NSTextAlignmentLeft;
    self.refreshButton.font=menu.font;
    self.refreshButton.contentTintColor=NSColor.labelColor;
    [self setRefreshTitle:@"刷新"];
    self.refreshButton.image=symbol(@"arrow.clockwise",13);
    self.refreshButton.imagePosition=NSImageLeft;
    [refreshRow addSubview:self.refreshButton];
    refreshItem.view=refreshRow; [menu addItem:refreshItem];
    self.permissionItem=[menu addItemWithTitle:@"设置鼠标访问权限…" action:@selector(openPermissions) keyEquivalent:@""];
    self.permissionItem.target=self; self.permissionItem.hidden=YES;
    NSButton *quit=[NSButton buttonWithTitle:@"退出" target:NSApp action:@selector(terminate:)];
    quit.frame=NSMakeRect(222,3,56,26);
    quit.bordered=NO; quit.alignment=NSTextAlignmentRight;
    quit.font=menu.font; quit.contentTintColor=NSColor.labelColor;
    quit.attributedTitle=[[NSAttributedString alloc] initWithString:@"退出" attributes:@{NSFontAttributeName:menu.font, NSForegroundColorAttributeName:NSColor.labelColor}];
    quit.keyEquivalent=@"q"; quit.keyEquivalentModifierMask=NSEventModifierFlagCommand;
    [refreshRow addSubview:quit];
    self.status.menu=menu;
    NSNotificationCenter *nc=NSWorkspace.sharedWorkspace.notificationCenter;
    [nc addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [nc addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:3600 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    self.timer.tolerance=30;
    [self refresh];
}
- (void)setRefreshTitle:(NSString *)title {
    self.refreshButton.attributedTitle=[[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName:self.refreshButton.font, NSForegroundColorAttributeName:NSColor.labelColor}];
}
- (void)openPermissions {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
}
- (void)sleep:(NSNotification *)n { self.sleeping=YES; }
- (void)wake:(NSNotification *)n { self.sleeping=NO; [self refresh]; }
- (void)refresh {
    if(self.busy || self.sleeping) return;
    self.busy=YES; self.refreshButton.enabled=NO; [self setRefreshTitle:@"正在刷新…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        @autoreleasepool {
            Readings r=query();
            if(diagnostic) fprintf(stderr,"menu query keyboard=%d mouse=%d charging=%d\n",r.keyboard,r.mouse,r.keyboardCharging);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.permissionItem.hidden=(r.mouse!=-2);
                self.card.keyboard=r.keyboard; self.card.mouse=r.mouse; self.card.keyboardCharging=r.keyboardCharging;
                self.card.needsDisplay=YES;
                self.status.button.toolTip=[NSString stringWithFormat:@"%@\n%@",[NSString stringWithFormat:@"键盘 %@%@",percent(r.keyboard),r.keyboardCharging?@" · 正在充电":@""],(r.mouse==-2?@"鼠标：需要输入监控权限":[@"鼠标 " stringByAppendingString:percent(r.mouse)])];
                self.busy=NO; self.refreshButton.enabled=YES; [self setRefreshTitle:@"刷新"];
            });
        }
    });
}
@end
static void selfTest(void) {
    uint8_t m[90]={2,0x1f,0,0,0,2,7,0x80,0,118};
    for(int i=2;i<88;i++)m[88]^=m[i];
    assert(parseMouse(m,90,0x1f)==46); assert(parseMouse(m,89,0x1f)==-1);
    assert(parseMouse(m,90,0x3f)==-1); m[88]^=1; assert(parseMouse(m,90,0x1f)==-1);
    m[9]=0;m[88]=0;for(int i=2;i<88;i++)m[88]^=m[i];assert(parseMouse(m,90,0x1f)==0);
    m[9]=255;m[88]=0;for(int i=2;i<88;i++)m[88]^=m[i];assert(parseMouse(m,90,0x1f)==100);
    uint8_t k[64]={2,0x12,1}; k[11]=63; assert(parseKeyboard(k,64)==63);
    assert(parseKeyboard(k,11)==-1); k[11]=101; assert(parseKeyboard(k,64)==-1);
    k[11]=0;assert(parseKeyboard(k,64)==0);
    k[9]=1;assert(parseKeyboardCharging(k,64));
    k[9]=0;assert(!parseKeyboardCharging(k,64));
    k[9]=2;assert(!parseKeyboardCharging(k,64));
    assert(!parseKeyboardCharging(k,9));
    k[1]=0xff;k[9]=1;assert(parseKeyboard(k,64)==-1);assert(!parseKeyboardCharging(k,64));
    puts("PASS: valid, zero/full, checksum, transaction, length and malformed replies");
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if(argc>1 && !strcmp(argv[1],"--version")){puts("PeripheralBattery 1.3.1");return 0;}
        if(argc>1 && !strcmp(argv[1],"--self-test")){selfTest();return 0;}
        if(argc>1 && !strcmp(argv[1],"--once")) {
            Readings r=query();printf("ROG keyboard: %s%s\nRazer mouse: %s\n",percent(r.keyboard).UTF8String,r.keyboardCharging?" (charging)":"",percent(r.mouse).UTF8String);
            return (r.keyboard<0 || r.mouse<0)?1:0;
        }
        diagnostic=argc>1 && !strcmp(argv[1],"--diagnostic");
        NSApplication *app=NSApplication.sharedApplication;
        // One menu bar instance; CLI --once remains independent.
        if([NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier].count>1)return 0;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        BatteryApp *delegate=[BatteryApp new]; app.delegate=delegate; [app run];
    }
    return 0;
}
