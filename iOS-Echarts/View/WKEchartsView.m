//
//  WKEchartsView.m
//  iOS-Echarts
//
//  Created by Pluto-Y on 30/12/2016.
//  Copyright © 2016 pluto-y. All rights reserved.
//

#import "WKEchartsView.h"
#import "PYJsonUtil.h"

@interface WKWebView() <WKScriptMessageHandler>

@property (readwrite, copy) WKWebViewConfiguration *configuration;

@end

@interface WKEchartsView() {
    // This params store the handler of the echart actions
    NSMutableDictionary<PYEchartAction, PYEchartActionHandler> *actionHandleBlocks;
    PYOption *option;
    NSString *bundlePath;
    NSString *localHtmlContents;
    PYEchartTheme _theme;
}

@end

@implementation WKEchartsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initAll];
    }
    return self;
}

- (void)dealloc {
    [[self configuration].userContentController removeAllUserScripts];
}

#pragma mark - custom functions
#pragma mark 初始化
/// Initialize
- (void)initAll {
    bundlePath = [[NSBundle mainBundle] pathForResource:@"iOS-Echarts" ofType:@"bundle"];
    NSBundle *echartsBundle;
    if (bundlePath != nil) { // If 'iOS-Echarts' is installed by Cocoapods and don't use 'use_frameworks!' command
        echartsBundle = [NSBundle bundleWithPath:bundlePath];
    } else { // If 'iOS-Echarts' is installed manually or use 'use_frameworks!' command
#if TARGET_OS_IPHONE
        echartsBundle = [NSBundle mainBundle];
#elif TARGET_OS_MAC
        echartsBundle = [NSBundle bundleWithPath:[NSBundle mainBundle].resourcePath];
#endif
        
        // If 'iOS-Echarts' is install by Cocoapods and use 'use_frameworks!' command
        if ([echartsBundle pathForResource:@"echarts" ofType:@"html"] == nil) {
            NSArray *allFrameworks = [echartsBundle pathsForResourcesOfType:@"framework" inDirectory:@"Frameworks"];
            for (NSString *path in allFrameworks) {
                if ([path hasSuffix:@"iOS_Echarts.framework"]) { // if the framework name has suffix 'iOS_Echarts.framework', I think it's iOS-Echart's framework
                    bundlePath = [path stringByAppendingString:@"/iOS-Echarts.bundle"];
                    echartsBundle = [NSBundle bundleWithPath:bundlePath];
                    break;
                }
            }
        }
    }
#if TARGET_OS_IPHONE
    bundlePath = [echartsBundle bundlePath];
#elif TARGET_OS_MAC
    bundlePath = [echartsBundle resourcePath];
#endif
    NSString *urlString = [echartsBundle pathForResource:@"echarts" ofType:@"html"];
    localHtmlContents =[[NSString alloc] initWithContentsOfFile:urlString encoding:NSUTF8StringEncoding error:nil];
    
    if (localHtmlContents == nil || [localHtmlContents isEqualToString:@""]) {
        NSLog(@"Error: Can't load echart's files.");
    }
    
    self.navigationDelegate = self;
    self.UIDelegate = self;
    self.scrollView.bounces = NO;
    self.scrollView.scrollEnabled = NO;
    
    
    
    NSString *js = @"var meta = document.createElement('meta'); meta.setAttribute('name', 'viewport'); meta.setAttribute('content', 'width=device-width'); document.getElementsByTagName('head')[0].appendChild(meta);";

    
    WKUserContentController *userContentController = self.configuration.userContentController;
    NSMutableArray<WKUserScript *> *array = [userContentController.userScripts mutableCopy];
    WKUserScript* fitWKUScript = nil;
    for (WKUserScript* wkUScript in array) {
        if ([wkUScript.source isEqual:js]) {
            fitWKUScript = wkUScript;
            break;
        }
    }
    if (!fitWKUScript) {
        fitWKUScript = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
        [userContentController addUserScript:fitWKUScript];
    }


    // set the view background is transparent
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    
    actionHandleBlocks = [[NSMutableDictionary alloc] init];

}

/**
 *  Load the web view request
 */
- (void)loadEcharts {
    [self loadHTMLString:localHtmlContents baseURL:[NSURL fileURLWithPath: bundlePath]];
}

/**
 *  Call the js method
 *
 *  @param methodWithParam The format:`[instance.]methodname(params)`
 */
- (void)callJsMethods:(NSString *)methodWithParam {
    [self evaluateJavaScript:methodWithParam completionHandler:nil];
}


/**
 *  Resize the main div in the `echarts.html`
 */
- (void)resizeDiv {
    float height = self.frame.size.height - 20;
    float width = self.frame.size.width;
    if (!CGSizeEqualToSize(_divSize, CGSizeZero)) {
        height = _divSize.height - 20;
        width = _divSize.width;
    } else {
        _divSize = CGSizeMake(width, height);
    }
    NSString *divSizeCss = [NSString stringWithFormat:@"'height:%.0fpx;width:%.0fpx;'", height, width];
    NSString *js = [NSString stringWithFormat:@"%@(%@)", @"resizeDiv", divSizeCss];
    [self callJsMethods:js];
}

#pragma mark - Echarts methods
/**
 *  Refresh echarts not re-load echarts
 *  The option is the last option you had set
 */
- (void)refreshEcharts {
    [self callJsMethods:@"myChart.refresh()"];
}

/**
 *  Refresh echart with the option
 *  You can call this method for refreshing not re-load the echart
 *
 *  @param newOption EChart's option
 */
- (void)refreshEchartsWithOption:(PYOption *)newOption {
    NSString *jsonStr = [PYJsonUtil getJSONString:newOption];
    PYLog(@"jsonStr:%@", jsonStr);
    [self callJsMethods:[NSString stringWithFormat:@"refreshWithOption(%@)", jsonStr]];
}

/**
 *  Set theme for echarts
 *  You can set the themes by echarts support, which prefix is `PYEchartTheme`
 *
 *  @param theme The theme name
 */
- (void)setTheme:(PYEchartTheme) theme {
    _theme = theme;
    PYLog(@"Theme is %@", theme);
    [self callJsMethods:[NSString stringWithFormat:@"myChart.setTheme(eval('%@'));", _theme]];
}

/**
 *  Add the echart action handler
 *
 *  @param name  The echart event name
 *  @param block The block handler
 */
- (void)addHandlerForAction:(PYEchartAction)name withBlock:(PYEchartActionHandler)block {
    [[self configuration].userContentController addScriptMessageHandler:self name:name];
    [actionHandleBlocks setObject:block forKey:name];
    [self callJsMethods:[NSString stringWithFormat:@"addEchartActionHandler(%@)",name]];
}

/**
 *  Remove the echart action hander
 *
 *  @param name The echart event name
 */
- (void)removeHandlerForAction:(PYEchartAction)name {
    [[self configuration].userContentController removeScriptMessageHandlerForName:name];
    [actionHandleBlocks removeObjectForKey:name];
    [self callJsMethods:[NSString stringWithFormat:@"removeEchartActionHandler(%@)",name]];
}

/**
 *  Set the option for echart
 *
 *  @param pyOption The echart option
 */
- (void)setOption:(PYOption *)pyOption {
    option = pyOption;
}

#pragma mark - Delegate
#pragma mark WKNavigationDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (option == nil) {
        NSLog(@"Warning: The option is nil.");
        [self callJsMethods:@"initEchartView()"];
        return ;
    }
    [self resizeDiv];
    
    NSString *jsonStr = [PYJsonUtil getJSONString:option];
    NSString *js;
    PYLog(@"%@",jsonStr);
    
    if (_noDataLoadingOption != nil) {
        PYLog(@"nodataLoadingOption:%@", [PYJsonUtil getJSONString:_noDataLoadingOption]);
        NSString *noDataLoadingOptionString = [NSString stringWithFormat:@"{\"noDataLoadingOption\":%@ \n}", [PYJsonUtil getJSONString:_noDataLoadingOption]];
        js = [NSString stringWithFormat:@"%@(%@, %@)", @"loadEcharts", jsonStr, noDataLoadingOptionString];
    } else {
        js = [NSString stringWithFormat:@"%@(%@)", @"loadEcharts", jsonStr];
    }
    [self callJsMethods:js];
    [self setTheme:_theme];
    for (NSString * name in actionHandleBlocks.allKeys) {
        PYLog(@"%@", [NSString stringWithFormat:@"addEchartActionHandler('%@')",name]);
        [self callJsMethods:[NSString stringWithFormat:@"addEchartActionHandler('%@')",name]];//
    }
//    if (self.eDelegate && [self.eDelegate respondsToSelector:@selector(echartsViewDidFinishLoad:)]) {
//        [self.eDelegate echartsViewDidFinishLoadz:self];
//    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = webView.URL;
    PYLog(@"%@", url);
    
    if (![[url.scheme lowercaseString] hasPrefix:@"pyechartaction"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    // get the action from the path
//    NSString *actionType = url.host;
// 
//    if ([kEchartActionObtainImg isEqualToString:actionType]) {
//        if (obtainImgCompletedBlock != nil) {
//            __weak typeof(obtainImgCompletedBlock) block = obtainImgCompletedBlock;
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
//                PY_IMAGE *image = nil;
//                NSString *imgBase64Str = [url.fragment stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
//                NSURL *url = [NSURL URLWithString:imgBase64Str];
//                NSData *imgData = [NSData dataWithContentsOfURL:url];
//                image = [PY_IMAGE imageWithData:imgData];
//                dispatch_sync(dispatch_get_main_queue(), ^{
//                    block(image);
//                });
//            });
//            
//        }
//    }
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    completionHandler();
    PYLog(@"%@", message);
}

#pragma mark WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    PYLog(@"name:%@, body:%@", message.name, message.body);
    PYEchartActionHandler block = actionHandleBlocks[message.name];
    // Check the action handle actions, if exists the block the invoke the block
    if (block != nil) {
        NSDictionary *params = (NSDictionary *)message.body;
        block(params);
    }
}


@end
