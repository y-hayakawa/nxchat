/* EmacsText.h
 *
 * You may freely copy, distribute, and reuse the code in this example.
 * NeXT disclaims any warranty of any kind, expressed or  implied, as to its
 * fitness for any particular use.
 *
 * Written by:  Julie Zelenski
 * Created:  Sept/91
 */

#import <appkit/appkit.h>


@interface EmacsText:Text
{
}

- initFrame:(NXRect *)fRect;

- (int)perform:(SEL)selector withSel:(SEL)helper;

- (int)positionForLineBegin;
- (int)positionForLineEnd;
- (int)positionForWordBegin;
- (int)positionForWordEnd;
- (int)positionForDocumentBegin;
- (int)positionForDocumentEnd;
- (int)nextPositionIfEmpty;

- moveToPosition:(SEL)command;
- deleteToPosition:(SEL)command;
- delete:(int)start :(int)end;
- yank;

- (BOOL) emacsEvent:(NXEvent *)event;
- keyDown:(NXEvent *)event;

@end
