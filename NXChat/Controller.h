/*
  NXChat -- an AI assistant for NEXTSTEP
  Yoshinori Hayakawa
  2025-07-31
  Version 0.2
 */


#import <appkit/appkit.h>

@interface Controller:Object
{
    id mainWindow ;
    id assistantScrollView ;
    id promptScrollView ;

    id prefPanel ;
    id infoPanel ;

    id ipAddressTextField ;
    id portNumberTextField ;

    int sockfd ;
    int server_port ;
    char server_ip[24] ;

    char *file_path ;
    char *file_basename ;
}

+ initialize ;

- appDidInit:sender ;
- (BOOL) connect ;
- appendTextToAssistantView:(const char *) string ;
- sendPromptToAssistant:sender ;
- (int) sockfd ;

- setFilename:(const char*) filename ;
- saveLogAs:sender ;
- saveLog:sender ;

- showInfoPanel:sender ;
- showPrefPanel:sender ;
- setServerInfo:sender ;

@end
