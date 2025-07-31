

/*
  MD(MarkDown) Text
  Yoshinori Hayakawa
 */

#import <appkit/appkit.h>


@interface MDText:Text
{
}

- initFrame:(NXRect *)fRect;
- initRTF:sender ;
- appendAsMarkDown:(char *) md_string ;

@end
