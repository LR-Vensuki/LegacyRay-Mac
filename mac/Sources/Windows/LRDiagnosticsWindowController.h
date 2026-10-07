/* diagnostics, console style: tabs for the daemon's live state, its log,
   the app's own activity and the pf rules in force, a bar of tools under
   them, and a privacy safe report to save or send */
#import <Cocoa/Cocoa.h>

@interface LRDiagnosticsWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate,
                                                               NSTabViewDelegate> {
    NSTabView *_tabs;
    NSTableView *_factsTable;
    NSTableView *_activityTable;
    NSTextView *_logView;
    NSTextView *_fwView;
    NSArray *_facts;
    NSArray *_activity;
}
@end

/* the whole report as text, links and addresses replaced */
void LRBuildDiagnosticReport(void (^done)(NSString *report));
