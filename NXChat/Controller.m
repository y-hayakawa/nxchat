/*
  NXChat -- an AI assistant for NEXTSTEP
  Yoshinori Hayakawa
  2025-07-31
  Version 0.2
 */


#import "Controller.h"

#import "MDText.h"
#import "EmacsText.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ctype.h>

#import <foundation/NSException.h>
#import <foundation/NSUtilities.h>

#import <mach/cthreads.h>
#import <objc/objc-runtime.h>

#include "jconv.h"

static void message_receiver(void *arg) ;

@implementation Controller

void MyTopLevelErrorHandler(NXHandler *errorState)
{
    if (errorState->code >= NSExceptionBase &&
        errorState->code <= NSLastException) {
        NSException *exception = (id) errorState->data1;
        // fprintf(stderr,"Error: %s %s\n",[exception exceptionName], [exception exceptionReason]) ;
        NSLog(@"%@: %@\n", [exception exceptionName], [exception exceptionReason]);
    }
}


+ initialize
{
    static NXDefaultsVector NXChatDefaults = {
        {"ServerIP", "127.0.0.1"},
        {"ServerPort", "12345"},
        {NULL, NULL}
    } ;
    
    NXRegisterDefaults("NXChat", NXChatDefaults) ;
    return self ;
}

- appDidInit:sender
{
    const char *ipaddr, *port ;

    ipaddr = NXGetDefaultValue("NXChat","ServerIP") ;
    port = NXGetDefaultValue("NXChat","ServerPort") ;

    objc_setMultithreaded(YES);

    NXSetTopLevelErrorHandler(MyTopLevelErrorHandler);

    strcpy(server_ip,ipaddr) ;
    server_port = atoi(port) ;
    if ([self connect]) {
        cthread_fork((cthread_fn_t)message_receiver ,(void *)self) ;
    } else {
        NXRunAlertPanel([NXApp appName],"Cannot connect to server. Please check the settings in Preferences.",0,0,0,0) ;
    }

    file_path = NULL ;
    file_basename = (char *)malloc(1024) ;

    [mainWindow makeFirstResponder:[promptScrollView docView]] ;

    return self ;
}

/*
 * Custom inet_aton implementation for dotted-quad IPv4 strings.
 * Returns 1 on success, 0 on failure.
 */
int inet_aton(const char *cp, struct in_addr *addr) {
    unsigned long val;
    int i;
    unsigned char octets[4];
    char *endp;

    for (i = 0; i < 4; i++) {
        if (!isdigit((unsigned char)*cp))
            return 0;
        val = strtoul(cp, &endp, 10);
        if (endp == cp || val > 255)
            return 0;
        octets[i] = (unsigned char)val;
        cp = endp;
        if (i < 3) {
            if (*cp != '.')
                return 0;
            cp++;
        }
    }
    /* Pack into network byte order */
    addr->s_addr = htonl((octets[0] << 24) |
                         (octets[1] << 16) |
                         (octets[2] << 8)  |
                         octets[3]);
    return 1;
}


- (BOOL) connect
{
    struct sockaddr_in serv_addr;

    /* Create socket */
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("socket");
        exit(1);
    }

    /* Server address setup */
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(server_port);
    if (!inet_aton(server_ip, &serv_addr.sin_addr)) {
        fprintf(stderr, "Invalid server IP: %s\n", server_ip);
        close(sockfd);
        return NO ;
    }

    /* Connect to server */
    if (connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("connect");
        close(sockfd);
        return NO ;
    }

    printf("Connected to %s:%d\n", server_ip, server_port);

    return YES ;
}


- appendTextToAssistantView:(const char *) string
{
    id text = [assistantScrollView docView] ;
    int length ;
    int ret ;
    unsigned char *out_buffer ;
    size_t out_len ;
    
    ret = utf8_to_eucjp(string, strlen(string), &out_buffer, &out_len) ;
    if (ret<0) {
        free(out_buffer) ;
        return nil ;
    }

    [mainWindow setDocEdited:YES] ;
#if 0
    length = [text byteLength] ;
    [text setSel:length :length] ;
    [text replaceSel:out_buffer] ;
#else
    [text appendAsMarkDown:out_buffer] ;
#endif
    [text scrollSelToVisible] ;

    [text display] ;

    free(out_buffer) ;

    return self ;
}

- sendPromptToAssistant:sender
{
    int n ;
    int length ;
    int ret ;
    char *buffer ;
    unsigned char *out_buffer ;
    size_t out_len ;
    id text = [promptScrollView docView] ;

    length = [text byteLength] ;

    if (length==0) return self ;

    buffer = (char *) malloc(sizeof(char)*length+1) ;

    buffer[length] = '\0' ;
    [text getSubstring:buffer start:0 length:length] ;

    ret = eucjp_to_utf8(buffer,length+1, &out_buffer, &out_len) ;
    if (ret<0) {
        perror("character conversion error");
        free(out_buffer) ;
        free(buffer) ;
        return nil ;
    }
    
    n = write(sockfd, out_buffer, out_len);
    if (n < 0) {
        NXRunAlertPanel([NXApp appName],"Cannot to send message to server. Please check settings and server\'s status.", 0,0,0,0) ;
        perror("write to socket");
        free(out_buffer) ;
        free(buffer) ;
        return nil ;
    }

    // erase prompt
    [text setSel:0 :length] ;
    [text replaceSel:""] ;
    [text scrollSelToVisible] ;
    [text display] ;

    free(buffer) ;
    free(out_buffer) ;
    return self ;
}

- (int) sockfd
{
    return sockfd ;
}

- showInfoPanel:sender
{
    if (!infoPanel) {
        [NXApp loadNibSection:"InfoPanel.nib" owner:self withNames:NO];
    }
    [infoPanel makeKeyAndOrderFront:sender];
    return self ;
}

- showPrefPanel:sender
{
    const char *ipaddr,*port ;

    if (!prefPanel) {
        [NXApp loadNibSection:"PrefPanel.nib" owner:self withNames:NO];
    }
    [prefPanel makeKeyAndOrderFront:sender];

    ipaddr = NXGetDefaultValue("NXChat","ServerIP") ;
    port = NXGetDefaultValue("NXChat","ServerPort") ;

    [ipAddressTextField setStringValue:ipaddr] ;
    [portNumberTextField setStringValue:port] ;

    return self ;
}

- setServerInfo:sender 
{
    const char *ipaddr,*port ;
    const char *ipaddr_orig,*port_orig ;
    static NXDefaultsVector newDefaults = {
        {"ServerIP", ""},
        {"ServerPort", ""},
        {NULL, NULL}
    } ;

    ipaddr_orig = NXGetDefaultValue("NXChat","ServerIP") ;
    port_orig = NXGetDefaultValue("NXChat","ServerPort") ;

    ipaddr = [ipAddressTextField stringValue] ;
    strcpy(server_ip,ipaddr) ;
    port = [portNumberTextField stringValue] ;
    server_port = atoi(port) ;

    newDefaults[0].value = alloca(256) ;
    strcpy(newDefaults[0].value, ipaddr) ;

    newDefaults[1].value = alloca(256) ;
    strcpy(newDefaults[1].value, port) ;    

    NXWriteDefaults("NXChat", newDefaults) ;

    if (strcmp(ipaddr_orig,ipaddr)!=0 || strcmp(port_orig,port)!=0)
        NXRunAlertPanel([NXApp appName],"Changes take effect after restarting.", 0,0,0,0) ;

    [prefPanel performClose:self] ;

    return self ;
}

- setFilename:(const char*) filename
{

    if (file_path) free(file_path) ;
    file_path = (char *) malloc(strlen(filename)+1) ;
    strcpy(file_path,filename);
    return self ;
}

- saveLogAs:sender
{
    id panel ;
    const char *dir ;
    char *file ;

    if (file_path==0) {
        dir = NXHomeDirectory() ;
        sprintf(file_basename,"chat_log") ;
    } else {
        file = rindex(file_path,'/');
        if (file) {
            dir = file_path ;
            *file = 0 ;
            file++ ;
            sprintf(file_basename,"%s",file) ;
        } else {
            dir = file_path ;
            sprintf(file_basename,"chat_log") ;
        }
    }
    
    panel = [SavePanel new] ;
    [panel setRequiredFileType: "rtf"] ;
    if ([panel runModalForDirectory:dir file:file_basename]) {
        id res ;
        const char *filename = [panel filename] ;
        [self setFilename: filename] ;
        res = [self saveLog:sender] ;
        return self ;
    }
    return nil ;
}

- saveLog:sender
{
    int fd ;
    id text = [assistantScrollView docView] ;
    NXStream *theStream ;
    
    if (file_path==NULL) return [self saveLogAs:sender] ;

    fd = open(file_path, O_WRONLY|O_CREAT|O_TRUNC, 0666) ;
    if (fd<0) {
        NXRunAlertPanel([NXApp appName],"Cannot save file:%s",0,0,0,strerror(errno)) ;
        return self ;
    }
    theStream = NXOpenFile(fd,NX_WRITEONLY) ;
    // [text writeText:theStream];
    [text writeRichText:theStream];
    NXClose(theStream) ;
    close(fd) ;
    return self ;
}


#define BUFSIZE 100000 

static void message_receiver(void *arg)
{
    id controller = (Controller *) arg ;
    int sockfd = [controller sockfd] ;
    int maxfd,n ;
    fd_set read_fds;
    char * recvbuf = (char *) malloc(BUFSIZE) ;

    // bzero(recvbuf, BUFSIZE) ;

    while (1) {
        FD_ZERO(&read_fds);
        FD_SET(sockfd, &read_fds);
        maxfd = sockfd;

        if (select(maxfd + 1, &read_fds, NULL, NULL, NULL) < 0) {
            perror("select");
            break;
        }

        /* Data from server */
        if (FD_ISSET(sockfd, &read_fds)) {
            n = read(sockfd, recvbuf, BUFSIZE - 1);
            if (n < 0) {
                perror("read from socket");
                break;
            } else if (n == 0) {
                /* Server closed connection */
                printf("Server closed connection.\n");
                break;
            }
            recvbuf[n] = 0 ;
            [controller appendTextToAssistantView:recvbuf] ;
        }
    }
    close(sockfd);
    free(recvbuf) ;
    return ;
}

@end
