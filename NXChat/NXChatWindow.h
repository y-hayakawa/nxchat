
#import <appkit/appkit.h>

@interface NXChatWindow:Window
{
    id sendButton ;
}

- (BOOL)commandKey:(NXEvent *)theEvent ;

@end
