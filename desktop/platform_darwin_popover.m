//go:build darwin

#import <AppKit/AppKit.h>
#include <math.h>
#import "platform_darwin_popover.h"
#import "platform_darwin_tray.h"

enum {
    FLPopoverActionStart = 1,
    FLPopoverActionPause,
    FLPopoverActionResume,
    FLPopoverActionFinish,
    FLPopoverActionAbort,
    FLPopoverActionRetry,
    FLPopoverToggleName,
    FLPopoverOpenDashboard,
    FLPopoverOpenHistory,
    FLPopoverOpenSettings,
    FLPopoverOpenFeedback,
};

static NSPanel *focusLinkStatusPanel;

static NSStackView *FLStack(NSUserInterfaceLayoutOrientation orientation, CGFloat spacing) {
    NSStackView *stack = [[[NSStackView alloc] init] autorelease];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = spacing;
    stack.detachesHiddenViews = YES;
    return stack;
}

static NSTextField *FLLabel(NSString *value, NSFont *font, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:value ?: @""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.cell.usesSingleLineMode = YES;
    label.cell.wraps = NO;
    [label.widthAnchor constraintLessThanOrEqualToConstant:292].active = YES;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

static NSDictionary *FLCapability(NSDictionary *state, NSString *action) {
    id value = state[action];
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static BOOL FLAllowed(NSDictionary *state, NSString *action) {
    return [FLCapability(state, action)[@"allowed"] boolValue];
}

static NSString *FLReason(NSDictionary *state, NSString *action) {
    return FLCapability(state, action)[@"reason"] ?: @"";
}

@interface FocusLinkPopoverViewController () {
    NSTextField *_statusLabel;
    NSTextField *_taskLabel;
    NSTextField *_taskHintLabel;
    NSTextField *_timerLabel;
    NSTextField *_timerHintLabel;
    NSTextField *_balanceLabel;
    NSTextField *_detailLabel;
    NSTextField *_nameField;
    NSButton *_nameToggleButton;
    NSButton *_primaryButton;
    NSButton *_secondaryButton;
    NSButton *_abortButton;
    NSButton *_dashboardButton;
    NSButton *_historyButton;
    NSButton *_settingsButton;
    NSButton *_feedbackButton;
    NSStackView *_contentStack;
    NSStackView *_sessionMetaRow;
    NSStackView *_timerCard;
    NSStackView *_sessionButtons;
    NSDictionary *_lastState;
    BOOL _busy;
    BOOL _nameEntryExpanded;
}
- (void)buttonPressed:(NSButton *)sender;
- (void)updatePrimaryButtonTextColor;
- (void)setStatusPanelHeight:(CGFloat)height;
- (CGFloat)preferredHeightForCurrentContent;
- (void)updateStatusPanelHeight;
@end

@implementation FocusLinkPopoverViewController

- (void)loadView {
    NSVisualEffectView *root = [[[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 320, 220)] autorelease];
    [root.widthAnchor constraintEqualToConstant:320].active = YES;
    root.material = NSVisualEffectMaterialPopover;
    root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    root.state = NSVisualEffectStateActive;
    root.wantsLayer = YES;
    root.layer.cornerRadius = 13;
    root.layer.masksToBounds = YES;

    NSStackView *stack = FLStack(NSUserInterfaceLayoutOrientationVertical, 4);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack = stack;
    [root addSubview:stack];

    NSStackView *header = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [header.widthAnchor constraintEqualToConstant:292].active = YES;
    _taskLabel = FLLabel(@"", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor);
    [_taskLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _statusLabel = FLLabel(@"作業開始前", [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
    [_statusLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_statusLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:_taskLabel];
    NSView *spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:spacer];
    [header addArrangedSubview:_statusLabel];
    [stack addArrangedSubview:header];

    _taskHintLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [stack addArrangedSubview:_taskHintLabel];

    _nameToggleButton = [self linkButtonWithTitle:@"作業名を追加" tag:FLPopoverToggleName];
    [stack addArrangedSubview:_nameToggleButton];
    _nameField = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    _nameField.placeholderString = @"作業名（任意）";
    _nameField.accessibilityLabel = @"作業名（任意）";
    _nameField.font = [NSFont systemFontOfSize:13];
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    _nameField.hidden = YES;
    [_nameField.heightAnchor constraintEqualToConstant:32].active = YES;
    [_nameField.widthAnchor constraintLessThanOrEqualToConstant:292].active = YES;
    [_nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [stack addArrangedSubview:_nameField];

    _timerCard = FLStack(NSUserInterfaceLayoutOrientationVertical, 3);
    _timerLabel = FLLabel(@"0:00:00", [NSFont monospacedDigitSystemFontOfSize:27 weight:NSFontWeightSemibold], NSColor.labelColor);
    _timerLabel.accessibilityLabel = @"作業時間";
    _timerHintLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [_timerCard addArrangedSubview:_timerLabel];
    [_timerCard addArrangedSubview:_timerHintLabel];
    [stack addArrangedSubview:_timerCard];

    _sessionMetaRow = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    _sessionMetaRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_sessionMetaRow.widthAnchor constraintEqualToConstant:292].active = YES;
    _balanceLabel = FLLabel(@"", [NSFont systemFontOfSize:12 weight:NSFontWeightMedium], NSColor.labelColor);
    _detailLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [_detailLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_sessionMetaRow addArrangedSubview:_balanceLabel];
    [_sessionMetaRow addArrangedSubview:_detailLabel];
    [stack addArrangedSubview:_sessionMetaRow];

    _primaryButton = [self buttonWithTitle:@"開始" tag:FLPopoverActionStart primary:YES];
    [_primaryButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [_primaryButton.widthAnchor constraintEqualToConstant:292].active = YES;
    [stack addArrangedSubview:_primaryButton];

    _sessionButtons = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    _secondaryButton = [self buttonWithTitle:@"終了" tag:FLPopoverActionFinish primary:NO];
    [_secondaryButton.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
    [_sessionButtons addArrangedSubview:_secondaryButton];
    _abortButton = [self linkButtonWithTitle:@"中止する" tag:FLPopoverActionAbort];
    _abortButton.contentTintColor = NSColor.systemRedColor;
    [_sessionButtons addArrangedSubview:_abortButton];
    [stack addArrangedSubview:_sessionButtons];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];

    NSStackView *footer = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 10);
    _dashboardButton = [self linkButtonWithTitle:@"ダッシュボード" tag:FLPopoverOpenDashboard];
    _historyButton = [self linkButtonWithTitle:@"記録" tag:FLPopoverOpenHistory];
    _settingsButton = [self linkButtonWithTitle:@"設定" tag:FLPopoverOpenSettings];
    _feedbackButton = [self linkButtonWithTitle:@"結果" tag:FLPopoverOpenFeedback];
    [footer addArrangedSubview:_dashboardButton];
    [footer addArrangedSubview:_historyButton];
    [footer addArrangedSubview:_settingsButton];
    [footer addArrangedSubview:_feedbackButton];
    [stack addArrangedSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:9],
    ]];
    self.view = root;
}

- (NSButton *)buttonWithTitle:(NSString *)title tag:(NSInteger)tag primary:(BOOL)primary {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(buttonPressed:)];
    button.tag = tag;
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = primary ? NSControlSizeLarge : NSControlSizeRegular;
    button.font = [NSFont systemFontOfSize:13 weight:primary ? NSFontWeightSemibold : NSFontWeightMedium];
    if (primary) {
        button.bezelColor = NSColor.controlAccentColor;
        button.contentTintColor = NSColor.whiteColor;
    }
    return button;
}

- (void)updatePrimaryButtonTextColor {
    NSColor *textColor = _primaryButton.enabled ? NSColor.whiteColor : NSColor.disabledControlTextColor;
    NSAttributedString *title = [[[NSAttributedString alloc] initWithString:_primaryButton.title attributes:@{ NSForegroundColorAttributeName: textColor }] autorelease];
    _primaryButton.attributedTitle = title;
}

- (NSButton *)linkButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(buttonPressed:)];
    button.tag = tag;
    button.bezelStyle = NSBezelStyleShadowlessSquare;
    button.bordered = NO;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.contentTintColor = NSColor.secondaryLabelColor;
    return button;
}

- (CGFloat)preferredHeightForCurrentContent {
    if (_contentStack == nil) {
        return 220;
    }
    [_contentStack layoutSubtreeIfNeeded];
    return ceil(_contentStack.fittingSize.height + 18);
}

- (void)updateStatusPanelHeight {
    [self.view layoutSubtreeIfNeeded];
    [self setStatusPanelHeight:[self preferredHeightForCurrentContent]];
}

- (void)setStatusPanelHeight:(CGFloat)height {
    if (focusLinkStatusPanel == nil || focusLinkStatusPanel.frame.size.height == height) {
        return;
    }
    NSRect frame = focusLinkStatusPanel.frame;
    CGFloat top = NSMaxY(frame);
    [focusLinkStatusPanel setContentSize:NSMakeSize(320, height)];
    [focusLinkStatusPanel setFrameOrigin:NSMakePoint(NSMinX(frame), top - NSHeight(focusLinkStatusPanel.frame))];
}

- (void)updateWithState:(NSDictionary *)state {
    NSDictionary *nextState = [state copy];
    [_lastState release];
    _lastState = nextState;

    NSString *status = state[@"status"] ?: @"idle";
    NSString *detail = state[@"detail"] ?: @"";
    BOOL isIdle = [status isEqualToString:@"idle"];
    BOOL isRunning = [status isEqualToString:@"running"];
    BOOL isPaused = [status isEqualToString:@"paused"];
    BOOL isPending = [status isEqualToString:@"pending"];
    BOOL hasTask = [state[@"hasTask"] boolValue];
    BOOL canRetry = FLAllowed(state, @"retry");

    _statusLabel.stringValue = state[@"statusLabel"] ?: @"作業開始前";
    _statusLabel.toolTip = _statusLabel.stringValue;
    _statusLabel.textColor = isRunning ? NSColor.systemGreenColor : (isPaused || isPending ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor);
    _taskLabel.stringValue = state[@"taskDescription"] ?: @"タスクがありません";
    _taskLabel.toolTip = _taskLabel.stringValue;
    _taskHintLabel.stringValue = state[@"taskHint"] ?: @"";
    _taskHintLabel.toolTip = _taskHintLabel.stringValue;
    _taskHintLabel.hidden = _taskHintLabel.stringValue.length == 0;
    _timerLabel.stringValue = state[@"elapsed"] ?: @"0:00:00";
    _timerHintLabel.stringValue = state[@"timerHint"] ?: @"";
    _timerHintLabel.toolTip = _timerHintLabel.stringValue;
    _timerHintLabel.hidden = _timerHintLabel.stringValue.length == 0;
    NSString *balance = state[@"balance"] ?: @"";
    _balanceLabel.stringValue = balance;
    if ([balance hasPrefix:@"このセッションの報酬残高"]) {
        _balanceLabel.stringValue = [balance stringByReplacingOccurrencesOfString:@"このセッションの報酬残高" withString:@"報酬残高"];
    } else if ([balance hasPrefix:@"確定残高"]) {
        _balanceLabel.stringValue = [balance stringByReplacingOccurrencesOfString:@"確定残高" withString:@"残高"];
    }
    _balanceLabel.toolTip = balance;
    _balanceLabel.accessibilityLabel = balance;
    _balanceLabel.hidden = _balanceLabel.stringValue.length == 0;
    _sessionMetaRow.hidden = balance.length == 0 && detail.length == 0;
    NSString *compactDetail = detail;
    if ([detail containsString:@"このセッションは記録専用です"]) {
        compactDetail = @"記録専用";
    } else if ([detail containsString:@"同期に失敗"]) {
        compactDetail = @"同期エラー";
    } else if ([detail containsString:@"サーバーへの作業状態を同期しています"] || [detail containsString:@"作業記録をサーバーへ同期しています"]) {
        compactDetail = @"同期中";
    } else if ([detail containsString:@"前回の作業結果を確認できます"]) {
        compactDetail = @"結果あり";
    } else if ([detail containsString:@"記録はこのMacに保存されます"]) {
        compactDetail = @"このMacに保存";
    }
    _detailLabel.stringValue = compactDetail;
    _detailLabel.toolTip = state[@"detailTooltip"] ?: detail;
    _detailLabel.accessibilityLabel = detail;
    _detailLabel.hidden = detail.length == 0;

    if (!isIdle) {
        _nameEntryExpanded = NO;
        _nameField.stringValue = @"";
    }
    _nameToggleButton.hidden = !isIdle || !hasTask;
    _nameToggleButton.title = _nameEntryExpanded ? @"作業名を閉じる" : @"作業名を追加";
    _nameField.hidden = !isIdle || !hasTask || !_nameEntryExpanded;
    _timerCard.hidden = isIdle;
    _sessionButtons.hidden = !(isRunning || isPaused);

    if (isIdle) {
        _primaryButton.hidden = NO;
        BOOL retryableStart = [state[@"startRetryable"] boolValue];
        _primaryButton.title = hasTask ? (retryableStart ? @"再試行" : @"作業を開始") : @"設定を開く";
        _primaryButton.tag = hasTask ? FLPopoverActionStart : FLPopoverOpenSettings;
        _primaryButton.enabled = !_busy && (hasTask ? FLAllowed(state, @"start") : YES);
        _primaryButton.toolTip = hasTask ? (retryableStart ? (state[@"detailTooltip"] ?: FLReason(state, @"start")) : FLReason(state, @"start")) : @"";
    } else if (isRunning) {
        _primaryButton.hidden = NO;
        _primaryButton.title = @"一時停止";
        _primaryButton.tag = FLPopoverActionPause;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"pause");
        _primaryButton.toolTip = FLReason(state, @"pause");
        _secondaryButton.title = @"終了";
        _secondaryButton.toolTip = FLAllowed(state, @"finish") ? @"" : FLReason(state, @"finish");
        _secondaryButton.tag = FLPopoverActionFinish;
        _secondaryButton.enabled = !_busy && FLAllowed(state, @"finish");
        _abortButton.enabled = !_busy && FLAllowed(state, @"abort");
    } else if (isPaused) {
        _primaryButton.hidden = NO;
        _primaryButton.title = @"作業を再開";
        _primaryButton.tag = FLPopoverActionResume;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"resume");
        _primaryButton.toolTip = FLReason(state, @"resume");
        _secondaryButton.title = @"終了";
        _secondaryButton.toolTip = FLAllowed(state, @"finish") ? @"" : FLReason(state, @"finish");
        _secondaryButton.tag = FLPopoverActionFinish;
        _secondaryButton.enabled = !_busy && FLAllowed(state, @"finish");
        _abortButton.enabled = !_busy && FLAllowed(state, @"abort");
    } else if (isPending) {
        _primaryButton.hidden = !canRetry;
        _primaryButton.title = @"記録を再試行";
        _primaryButton.tag = FLPopoverActionRetry;
        _primaryButton.enabled = !_busy && canRetry;
        _primaryButton.toolTip = FLReason(state, @"retry");
    }

    _dashboardButton.enabled = !_busy;
    _historyButton.enabled = !_busy;
    _settingsButton.enabled = !_busy;
    _feedbackButton.enabled = !_busy && [state[@"hasResult"] boolValue];
    _feedbackButton.hidden = ![state[@"hasResult"] boolValue];
    [self updatePrimaryButtonTextColor];
    [self updateStatusPanelHeight];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy) {
        _detailLabel.stringValue = @"処理中";
        _detailLabel.toolTip = @"処理しています…";
        _detailLabel.accessibilityLabel = _detailLabel.toolTip;
        _detailLabel.hidden = NO;
        _sessionMetaRow.hidden = NO;
        _primaryButton.enabled = NO;
        _secondaryButton.enabled = NO;
        _abortButton.enabled = NO;
        _dashboardButton.enabled = NO;
        _historyButton.enabled = NO;
        _settingsButton.enabled = NO;
        _feedbackButton.enabled = NO;
        [self updateStatusPanelHeight];
    } else if (_lastState != nil) {
        [self updateWithState:_lastState];
    }
    [self updatePrimaryButtonTextColor];
}

- (void)dealloc {
    [_lastState release];
    [super dealloc];
}

- (void)buttonPressed:(NSButton *)sender {
    if (_busy) return;

    switch (sender.tag) {
        case FLPopoverToggleName:
            _nameEntryExpanded = !_nameEntryExpanded;
            _nameToggleButton.title = _nameEntryExpanded ? @"作業名を閉じる" : @"作業名を追加";
            _nameField.hidden = !_nameEntryExpanded;
            if (_nameEntryExpanded) {
                [[self.view window] makeFirstResponder:_nameField];
            }
            [self updateStatusPanelHeight];
            return;
        case FLPopoverActionStart:
            FocusLinkDispatchPopoverAction("start", [_nameField.stringValue UTF8String]);
            return;
        case FLPopoverActionPause:
            FocusLinkDispatchPopoverAction("pause", "");
            return;
        case FLPopoverActionResume:
            FocusLinkDispatchPopoverAction("resume", "");
            return;
        case FLPopoverActionFinish:
            FocusLinkDispatchPopoverAction("finish", "");
            return;
        case FLPopoverActionAbort:
            FocusLinkDispatchPopoverAction("abort", "");
            return;
        case FLPopoverActionRetry:
            FocusLinkDispatchPopoverAction("retry", "");
            return;
        case FLPopoverOpenDashboard:
            FocusLinkDispatchOpenPage("session");
            return;
        case FLPopoverOpenHistory:
            FocusLinkDispatchOpenPage("history");
            return;
        case FLPopoverOpenSettings:
            FocusLinkDispatchOpenPage("settings");
            return;
        case FLPopoverOpenFeedback:
            FocusLinkDispatchOpenPage("feedback");
            return;
        default:
            return;
    }
}

@end

static FocusLinkPopoverViewController *focusLinkPopoverViewController;

static void FLUpdatePopoverOnMainThread(NSDictionary *state) {
    if (state == nil || focusLinkPopoverViewController == nil) return;

    // Go の Cgo コールバック中に AppKit のビューを同期更新すると、イベント処理へ再入する。
    NSDictionary *retainedState = [state copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        FocusLinkPopoverViewController *viewController = focusLinkPopoverViewController;
        if (viewController != nil) {
            [viewController updateWithState:retainedState];
        }
        [retainedState release];
    });
}

void FocusLinkConfigureStatusPanel(NSPanel *panel) {
    focusLinkStatusPanel = panel;
    focusLinkPopoverViewController = [[FocusLinkPopoverViewController alloc] init];
    panel.contentViewController = focusLinkPopoverViewController;
    panel.backgroundColor = NSColor.clearColor;
    panel.opaque = NO;
    panel.hasShadow = YES;
    panel.level = NSStatusWindowLevel;
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;
    // 非アクティブな常駐アプリでも表示し、外側クリックは監視側で閉じる。
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;
    // アプリを前面化せず、メニューバーから開く操作パネルとして扱う。
    if (@available(macOS 10.14, *)) {
        panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
    panel.contentSize = NSMakeSize(320, 220);
}

void FocusLinkUpdatePopover(const char *stateJSON) {
    if (stateJSON == NULL) return;
    @autoreleasepool {
        NSString *json = [NSString stringWithUTF8String:stateJSON];
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error == nil && [parsed isKindOfClass:[NSDictionary class]]) {
            FLUpdatePopoverOnMainThread(parsed);
        }
    }
}

void FocusLinkSetPopoverBusy(int busy) {
    BOOL value = busy != 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        FocusLinkPopoverViewController *viewController = focusLinkPopoverViewController;
        [viewController setBusy:value];
    });
}
