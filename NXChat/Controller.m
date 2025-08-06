/*
  NXChat -- an AI assistant for NEXTSTEP
  Yoshinori Hayakawa
  2025-08-06
  Version 0.3
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

/* socket_hander -------------------------- */
static void socket_handler(int fd, void *arg) ;
#define BUFSIZE 65536
static char * recvbuf ;
static int bufused ;
static char * sendbuf ;
static int sendlen=0 ;
static int sendbufsize ;
/* ----------------------------------------- */

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

    objc_setMultithreaded(NO);

    ipaddr = NXGetDefaultValue("NXChat","ServerIP") ;
    port = NXGetDefaultValue("NXChat","ServerPort") ;

    NXSetTopLevelErrorHandler(MyTopLevelErrorHandler);

    strcpy(server_ip,ipaddr) ;
    server_port = atoi(port) ;

    if ([self connect]) {
        recvbuf = (char *) malloc(BUFSIZE) ;
        bufused = 0 ;
        sendbuf = (char *) malloc(BUFSIZE) ;
        sendbuf[0]=0 ;
        sendlen = 0 ;
        sendbufsize = BUFSIZE ;
        DPSAddFD(sockfd, (DPSFDProc) socket_handler, (id) self, NX_MODALRESPTHRESHOLD);
    } else {
        NXRunAlertPanel([NXApp appName],"Cannot connect to the server. Please verify that the server is running and check the settings in Preferences.",0,0,0,0) ;
    }

    file_path = NULL ;
    file_basename = (char *)malloc(1024) ;

    [assistantScrollView setDynamicScrolling:YES];
    [[promptScrollView docView] setSel:0 :0] ;

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

    fprintf(stderr,"Connected to %s:%d\n", server_ip, server_port);

    return YES ;
}

- disconnect 
{
    DPSRemoveFD(sockfd) ;
    close(sockfd) ;
    sockfd = -1 ;
    return self ;
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

#if 0  /* display plain text */
    length = [text charLength] ;
    [text setSel:length :length] ;
    [text replaceSel:out_buffer] ;
    [text scrollSelToVisible] ;
#else  /* convert Markdown to RTF */
    [text appendAsMarkDown:out_buffer] ;
#endif

    [text update] ;
    [[promptScrollView docView] setSel:0:0] ;
    [messageTextField setStringValue:""] ;

    free(out_buffer) ;

    return self ;
}

- sendPromptToAssistant:sender
{
    int n ;
    int byte_length ;
    int ret ;
    char *buffer ;
    unsigned char *out_buffer ;
    size_t out_len ;
    id text = [promptScrollView docView] ;

    byte_length = [text byteLength] ;

    if (byte_length==0) return self ;

    buffer = (char *) malloc(sizeof(char)*byte_length+1) ;

    buffer[byte_length] = '\0' ;
    [text getSubstring:buffer start:0 length:[text charLength]] ;

    ret = eucjp_to_utf8(buffer,byte_length+1, &out_buffer, &out_len) ;
    if (ret<0) {
        perror("character conversion error");
        free(out_buffer) ;
        free(buffer) ;
        return nil ;
    }
    
    n = write(sockfd, out_buffer, out_len);
    if (n < 0) {
        NXRunAlertPanel([NXApp appName],"Cannot connect to the server. Please verify that the server is running.", 0,0,0,0) ;
        perror("write to socket");
        free(out_buffer) ;
        free(buffer) ;
        return nil ;
    }

    // erase prompt
    [text setSel:0 :[text charLength]] ;
    [text replaceSel:""] ;
    [text scrollSelToVisible] ;
    [text display] ;

    [messageTextField setStringValue:"Waiting for server\'s response..."] ;

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

void *my_memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = (const unsigned char *)s;
    unsigned char uc = (unsigned char)c;
    size_t i ;
    for (i = 0; i < n; ++i) {
        if (p[i] == uc) {
            return (void *)(p + i);
        }
    }
    return NULL;
}

// In AppKit, GUI operations must be performed on a single thread. 
// However, in versions up to v0.2, there were instances where Views were manipulated 
// on a separate thread, which occasionally caused hangs. 
// Starting from v0.3, I revised the implementation to use a DPS handler 
// to wait for data from the server.

static void socket_handler (int sockfd, void * arg)
// DPS handler for output from subprocess
{
    id controller = (Controller *) arg ;
    int n,processed ;

    n = read(sockfd, recvbuf + bufused, BUFSIZE - 1 - bufused);
    if (n < 0) {
        if (errno == EINTR) return ;
        perror("read from socket");
        return;
    } else if (n == 0) {
        id retobj ;
        fprintf(stderr,"Server closed connection.\n");
        retobj = [controller disconnect] ;
        return;
    }

    bufused += n ;
    recvbuf[bufused]=0 ;

    processed = 0;
    while (bufused - processed > 0) {
        char *nul = memchr(recvbuf + processed, '\0', bufused - processed);
        if (nul) {
            char save ;
            int msglen = nul - (recvbuf + processed);
            save = recvbuf[processed + msglen];
            recvbuf[processed + msglen] = 0;
            sendlen += msglen ; // msglen doesn't count NULL
            if (sendlen > sendbufsize) {
                sendbufsize = sendlen + BUFSIZE ;
                sendbuf = (char *) realloc(sendbuf, sendbufsize) ;
            }
            strncat(sendbuf, recvbuf + processed, msglen) ;
            recvbuf[processed + msglen] = save;
            processed += (msglen + 1) ;
        } else {
            break;
        }
    }

    if (processed > 0) {
        if (bufused > processed) {
            memmove(recvbuf, recvbuf + processed, bufused - processed);
        }
        bufused -= processed;
    }

    if (sendlen > 0) {
        id retobj ;
        retobj = [controller appendTextToAssistantView:sendbuf];
        sendlen = 0 ;
        sendbuf[0] = 0 ;
    }
    return ;
}

@end
