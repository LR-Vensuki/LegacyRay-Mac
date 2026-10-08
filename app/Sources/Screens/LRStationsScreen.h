/* the station log: every server grouped under its subscription's brass plate,
   with latency readings, collapsing, arranging and the per section and per
   station menus. on the ipad it is the left (or lower) pane of the receiver */
#import "LRScreen.h"

@interface LRStationsScreen : LRScreen <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_table;
    UIView *_empty;
    BOOL _emptyOffline;    /* _empty is the daemon-unreachable variant */
    NSArray *_rows;        /* flattened: NSDictionary kind/section/server */
    BOOL _embedded;
    BOOL _arranging;
}
@property (nonatomic, assign) BOOL embedded;
@end
