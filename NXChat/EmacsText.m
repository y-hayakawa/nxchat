/* EmacsText.m
 *
 *  EmacsText is a subclass of Text which adds support for
 * keyboard bindings commonly used by the emacs editor.
 *
 * You may freely copy, distribute, and reuse the code in this example.
 * NeXT disclaims any warranty of any kind, expressed or  implied, as to its
 * fitness for any particular use.
 *
 * Written by:  Julie Zelenski
 * Created:  Sept/91
 */

#import "EmacsText.h"

@implementation EmacsText

/** This is the charCode offset for Control keys from Encoding Vectors Tech Doc **/

#define CONTROL_OFFSET (unsigned short)0x40


/** Cursor Movement Commands **/

#define CTRL_A ('A'  - CONTROL_OFFSET)
#define CTRL_B ('B'  - CONTROL_OFFSET)
#define CTRL_E ('E'  - CONTROL_OFFSET)
#define CTRL_F ('F'  - CONTROL_OFFSET)
#define CTRL_N ('N'  - CONTROL_OFFSET)
#define CTRL_P ('P'  - CONTROL_OFFSET)
#define ALT_LESS ((unsigned short)0xa3)
#define ALT_GREATER ((unsigned short) 0xb3)
#define ALT_B ((unsigned short) 0xe5)
#define ALT_F ((unsigned short) 0xa6)

/** Delete Commands  **/

#define CTRL_D ('D'  - CONTROL_OFFSET)
#define CTRL_K ('K'  - CONTROL_OFFSET)
#define CTRL_O ('O'  - CONTROL_OFFSET)
#define CTRL_Y ('Y'  - CONTROL_OFFSET)
#define ALT_D ((unsigned short) 0x44)
#define ALT_H ((unsigned short) 0xe3)



typedef struct _sel
{
    unsigned short charCode;
    SEL selector;
    SEL positionSelector;
    char *selectorString;
    char *positionSelectorString;
} SelectorItem;

static SelectorItem emacsMetaKeys[] = 
{
{ALT_B, 0, 0, "moveToPosition:", "positionForWordBegin"},
{ALT_F, 0, 0, "moveToPosition:", "positionForWordEnd"},
{ALT_LESS, 0, 0, "moveToPosition:", "positionForDocumentBegin"},
{ALT_GREATER, 0, 0, "moveToPosition:", "positionForDocumentEnd"},
{ALT_D, 0, 0, "deleteToPosition:", "positionForWordEnd"},
{ALT_H, 0, 0, "deleteToPosition:", "positionForWordBegin"},
{0}
};

static SelectorItem emacsControlKeys[] = 
{
{CTRL_A, 0, 0, "moveToPosition:", "positionForLineBegin"},
{CTRL_E, 0, 0, "moveToPosition:", "positionForLineEnd"},
{CTRL_K, 0, 0, "deleteToLineEnd", 0},
{CTRL_D, 0, 0, "deleteToPosition:", "nextPositionIfEmpty"},
{CTRL_Y, 0, 0, "yank", 0},
{0}
};

unsigned short emacsFilter (unsigned short
    charCode, int flags, unsigned short charSet)
{
    if (flags & NX_CONTROLMASK) 
    {         
	switch(charCode) {
	    case CTRL_F:
		return NX_RIGHT;
	    case CTRL_B:
	    	return NX_LEFT;
	    case CTRL_N:
	    	return NX_DOWN;
	    case CTRL_P:
	    	return NX_UP;
	    default: break;
	}
    } 
    return NXEditorFilter(charCode, flags, charSet);
}


int GetPrevious(NXStream *s)
{
     int pos;
     int ch;
     
     pos = NXTell(s);
     if (pos <= 0) return EOF;
     NXSeek(s, --pos, NX_FROMSTART);
     ch = NXGetc(s);
     NXUngetc(s);
     return ch;
}

// Complete the build of the selector tables
+initialize
{
    SelectorItem *cur;

    for (cur = emacsMetaKeys; cur->charCode; cur++)
    {
	cur->selector = sel_getUid(cur->selectorString);
	cur->positionSelector = sel_getUid(cur->positionSelectorString);
    }

    for (cur = emacsControlKeys; cur->charCode; cur++)
    {
	cur->selector = sel_getUid(cur->selectorString);
	cur->positionSelector = sel_getUid(cur->positionSelectorString);
    }
    return self;
}

- (int)positionForLineBeginActual
/* Not currently in use.  Looks for newline to find actual paragraph begin.
 */
{
    NXStream *s = [self stream];
    int pos;
    int ch;
    
    if (spN.cp < 0) return 0; // Is this the right thing to do here?

    NXSeek(s, sp0.cp, NX_FROMSTART);
    while (((ch = GetPrevious(s)) != EOF) && (ch != '\n'));
    pos = NXTell(s);
    if (ch != EOF) pos++;
    return pos;
}

- (int)positionForLineEndActual
/* Not currently in use.  Looks for newline to find actual paragraph end.
 */
{
    NXStream *s = [self stream];

    int pos;
    int ch;
    int max = [self textLength];
    
    if (spN.cp < 0) return 0; 
    if (spN.cp > max) return max;

    NXSeek(s, spN.cp, NX_FROMSTART);
    while (((ch = NXGetc(s)) != EOF) && (ch != '\n'));
    pos = NXTell(s);
    if (ch != EOF) pos--;
    return pos;
}

- (int)positionForLineEndVisual
/* This uses the break array to find the visual line end.  
 * However, it subtracts one from the position because of that behavior 
 * of the Text object that makes the position at the end of one line 
 * the same character position a the beginning of next line.  Seems to
 * be no way to position the insertion point at the end of the line.
 * Bummer.
 */
{
    int lineLength;
    int line;
    
    line = (spN.line /sizeof(NXLineDesc));
    lineLength = theBreaks->breaks[line] & 0x3fff;
    lineLength--; // Notice the hack....
    return (spN.c1st + lineLength);
}

- (int)positionForLineBeginVisual
{
    return (sp0.c1st);
}

/** BIG FAT HAIRY NOTE
 * This is how to change CTRL-A, CTRL-E, CTRL-K to use paragraph ends
 * (actual newlines) instead of visual line breaks.  Have the position
 * for line end methods call to the position for actual rather than
 * visual.
 */

- (int)positionForLineBegin
{
    return [self positionForLineBeginVisual];
}

- (int)positionForLineEnd
{
    return [self positionForLineEndVisual];

}

- (int)nextPositionIfEmpty
{
     if (sp0.cp == spN.cp) 
	return spN.cp + 1;
    else
	return spN.cp;
}

/* This is my quick decision on what characters count as a word, and which
 * don't.  The correct way to do this is to parse the ClickTable, but the
 * documentation is so incredibly sparse on this one....
 */
 
#define NORMAL_CHAR(ch) (((ch >= 'a') && (ch <= 'z')) || ((ch >= 'A') && (ch <= 'Z')) ||((ch >= '0') && (ch <= '9')) || (ch == '\'')|| (ch == '_'))


- (int)positionForWordEnd
{
    NXStream *s = [self stream];

    int pos;
    int ch;
    int max = [self textLength];
    
    if (spN.cp < 0) return 0; 	// boundary conditions?  Is this right idea?
    if (spN.cp > max) return max;

    NXSeek(s, spN.cp, NX_FROMSTART);
    while ((ch = NXGetc(s)) != EOF && !NORMAL_CHAR(ch)); // skip white space
    while ((ch = NXGetc(s)) != EOF && NORMAL_CHAR(ch));	// jump normal chars
    pos = NXTell(s);
    if (ch != EOF) pos--;
    return pos;
}

- (int)positionForWordBegin
{
    NXStream *s = [self stream];

    int pos;
    int ch;
    int max = [self textLength];
    
    if (spN.cp < 0) return 0; 	// boundary conditions?  Is this right idea?
    if (spN.cp > max) return max;

    NXSeek(s, sp0.cp, NX_FROMSTART);
    while ((ch = GetPrevious(s)) != EOF && !NORMAL_CHAR(ch)); // skip white space
    while ((ch = GetPrevious(s)) != EOF && NORMAL_CHAR(ch)); // jump normal chars
    pos = NXTell(s);
    if (ch != EOF) pos++;
    return pos;
}

- (int) positionForDocumentEnd
{
     return [self textLength];
}

- (int) positionForDocumentBegin
{
     return 0;
}

- moveToPosition:(SEL)command
{
    int pos;
    
    pos = (int)[self perform:command];
    [self setSel:pos :pos];
    [self scrollSelToVisible];
    return self;
}

- deleteToPosition:(SEL)command
/* Entry point for delete forward/backward word
 */
{
    int pos;
    int start,end;
    
    pos = (int)[self perform:command];
    if (pos > spN.cp) 
    { 	// if position extends to the right
    	start = sp0.cp;
	end = pos;
    } 
    else 
    {		// else position extends to the left
    	start = pos;
	end = spN.cp;
    }
    [self delete:start :end];
    return self;
}

- delete:(int)start :(int)end
/* Entry point for all deletes done for Emacs bindings.  Turns off 
 * autodisplay to avoid flicker and other unwanted drawing artifacts.
 * Calls cut and uses the Pasteboard to implement yank.  It is possible
 * to implement separate Emacs kill buffer, but it would be a bit of
 * hassle, because you need a Change object to keep both the runs and
 * the text that is yanked.  You can do it quick by storing only ASCII
 * text, which is not a good idea.  (Actually, to be correct, this is
 * all that Edit does, but who wants to use Edit for a role model?)
 */
{
    if (end - start) 
    {
	[self setAutodisplay:NO];
	[self setSel:start :end];
	[self cut:self];
	[[self setAutodisplay:YES] display];
    }
    return self;
}


- deleteToLineEnd
/* Somewhat icky hack has to handle the special case for deleting at end 
 * of line.  If in middle of line, don't delete the new line.  If at the 
 * very end of the line, do delete the new line.
 */
{
    int pos;
    int start,end;
    
    pos = [self positionForLineEnd];
    start = sp0.cp;
    end = pos;
    if (start == end) {// If already at end of line
	int line;
	int endsWithNewLine;
	
	line = (spN.line /sizeof(NXLineDesc));
	endsWithNewLine = theBreaks->breaks[line] & 0x4000;

	if (endsWithNewLine) 
	    end++;
	else  // Bail on case where at visual end of line, but no newline
	    return self;
    }
    [self delete:start :end];
    return self;
}


- yank
{
    [self paste:self];
    return self;
}


- (BOOL) emacsEvent:(NXEvent *)event
{
    SelectorItem *cur;
    unsigned charCode = event->data.key.charCode;
    
    if (event->flags & NX_CONTROLMASK) 
    {  
    	cur = emacsControlKeys;
			
	while (cur->charCode && (cur->charCode != charCode)) cur++;
	if (cur->charCode) 
	{
	    [self perform:cur->selector 
	    	withSel:(cur->positionSelector? cur->positionSelector : 0)];
	    return YES;
	}
    }
    if (event->flags & NX_ALTERNATEMASK) 
    {  
    	cur = emacsMetaKeys;
			
	while (cur->charCode && (cur->charCode != charCode)) cur++;
	if (cur->charCode) 
	{
	    [self perform:cur->selector 
	    	withSel:(cur->positionSelector? cur->positionSelector : 0)];
	    return YES;
	}
    }
    return NO;
}

- keyDown:(NXEvent *)event
{
    if ([self emacsEvent:event]) 
	return self;
    else
	return [super keyDown:event];
}

- (int)perform:(SEL)selector withSel:(SEL)helper 
{
    int   (*func)(id,SEL,SEL); 
	
    func = (int (*)(id,SEL,SEL))[self methodFor:selector];
    return (* func)(self, selector, helper);
}

- initFrame:(NXRect *)fRect
{
    NXRect r = *fRect;
    [super initFrame:fRect];
    [self setMonoFont:NO];
    [self setBackgroundGray:NX_WHITE];
    [self setOpaque:YES];
    [self setCharFilter:(NXCharFilterFunc)emacsFilter];
    [self notifyAncestorWhenFrameChanged: YES];
    [self setVertResizable:YES];
    [self setMinSize:&r.size];
    r.size.height = 1.0e30;
    [self setMaxSize:&r.size];
    return self;
}


@end
