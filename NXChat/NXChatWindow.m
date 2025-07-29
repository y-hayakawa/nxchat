
#import "NXChatWindow.h"

@implementation NXChatWindow

- (BOOL)commandKey:(NXEvent *)theEvent
{
    // command + return
    if ((theEvent->flags & NX_COMMANDMASK)  &&  theEvent->data.key.keyCode == 0x1c ) {
        [sendButton performClick:self] ;
        return YES ;
    } else {
        return NO ;
    }
}

@end


