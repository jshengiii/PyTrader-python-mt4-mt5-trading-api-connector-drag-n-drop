//+------------------------------------------------------------------+
//|                                        Pytrader_MT5_EA_V2.01.mq5 |
//|                           Copyright 2020, Deeptrade.ml / Branly. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, Deeptrade.ml / Branly."
#property link      "https://www.mql5.com"
#property version   "2.01"
#property description "Coded by Branly"
#property strict


// --------------------------------------------------------------------
// Include socket library, asking for event handling
// --------------------------------------------------------------------
#define SOCKET_LIBRARY_USE_EVENTS
// -------------------------------------------------------------
// Winsock constants and structures
// -------------------------------------------------------------

#define SOCKET_HANDLE32       uint
#define SOCKET_HANDLE64       ulong
#define AF_INET               2
#define SOCK_STREAM           1
#define IPPROTO_TCP           6
#define INVALID_SOCKET32      0xFFFFFFFF
#define INVALID_SOCKET64      0xFFFFFFFFFFFFFFFF
#define SOCKET_ERROR          -1
#define INADDR_NONE           0xFFFFFFFF
#define FIONBIO               0x8004667E
#define WSAWOULDBLOCK         10035

struct sockaddr {
   short family;
   ushort port;
   uint address;
   ulong ignore;
};

struct linger {
   ushort onoff;
   ushort linger_seconds;
};

// -------------------------------------------------------------
// DLL imports
// -------------------------------------------------------------


#import "ws2_32.dll"
   // Imports for 32-bit environment
   SOCKET_HANDLE32 socket(int, int, int); // Artificially differs from 64-bit version based on 3rd parameter
   int connect(SOCKET_HANDLE32, sockaddr&, int);
   int closesocket(SOCKET_HANDLE32);
   int send(SOCKET_HANDLE32, uchar&[],int,int);
   int recv(SOCKET_HANDLE32, uchar&[], int, int);
   int ioctlsocket(SOCKET_HANDLE32, uint, uint&);
   int bind(SOCKET_HANDLE32, sockaddr&, int);
   int listen(SOCKET_HANDLE32, int);
   SOCKET_HANDLE32 accept(SOCKET_HANDLE32, int, int);
   int WSAAsyncSelect(SOCKET_HANDLE32, int, uint, int);
   int shutdown(SOCKET_HANDLE32, int);
   
   // Imports for 64-bit environment
   SOCKET_HANDLE64 socket(int, int, uint); // Artificially differs from 32-bit version based on 3rd parameter
   int connect(SOCKET_HANDLE64, sockaddr&, int);
   int closesocket(SOCKET_HANDLE64);
   int send(SOCKET_HANDLE64, uchar&[], int, int);
   int recv(SOCKET_HANDLE64, uchar&[], int, int);
   int ioctlsocket(SOCKET_HANDLE64, uint, uint&);
   int bind(SOCKET_HANDLE64, sockaddr&, int);
   int listen(SOCKET_HANDLE64, int);
   SOCKET_HANDLE64 accept(SOCKET_HANDLE64, int, int);
   int WSAAsyncSelect(SOCKET_HANDLE64, long, uint, int);
   int shutdown(SOCKET_HANDLE64, int);

   // gethostbyname() has to vary between 32/64-bit, because
   // it returns a memory pointer whose size will be either
   // 4 bytes or 8 bytes. In order to keep the compiler
   // happy, we therefore need versions which take 
   // artificially-different parameters on 32/64-bit
   uint gethostbyname(uchar&[]); // For 32-bit
   ulong gethostbyname(char&[]); // For 64-bit

   // Neutral; no difference between 32-bit and 64-bit
   uint inet_addr(uchar&[]);
   int WSAGetLastError();
   uint htonl(uint);
   ushort htons(ushort);
#import

// For navigating the Winsock hostent structure, with indescribably horrible
// variation between 32-bit and 64-bit
#import "kernel32.dll"
   void RtlMoveMemory(uint&, uint, int);
   void RtlMoveMemory(ushort&, uint, int);
   void RtlMoveMemory(ulong&, ulong, int);
   void RtlMoveMemory(ushort&, ulong, int);
#import

// -------------------------------------------------------------
// Forward definitions of classes
// -------------------------------------------------------------

class ClientSocket;
class ServerSocket;


// -------------------------------------------------------------
// Client socket class
// -------------------------------------------------------------

class ClientSocket
{
   private:
      // Need different socket handles for 32-bit and 64-bit environments
      SOCKET_HANDLE32 mSocket32;
      SOCKET_HANDLE64 mSocket64;
      
      // Other state variables
      bool mConnected;
      int mLastWSAError;
      string mPendingReceiveData; // Backlog of incoming data, if using a message-terminator in Receive()
      
      // Event handling
      bool mDoneEventHandling;
      void SetupSocketEventHandling();
      
   public:
      // Constructors for connecting to a server, either locally or remotely
      ClientSocket(ushort localport);
      ClientSocket(string HostnameOrIPAddress, ushort port);

      // Constructors used by ServerSocket() when accepting a client connection
      ClientSocket(ServerSocket* ForInternalUseOnly, SOCKET_HANDLE32 ForInternalUseOnly_clientsocket32);
      ClientSocket(ServerSocket* ForInternalUseOnly, SOCKET_HANDLE64 ForInternalUseOnly_clientsocket64);

      // Destructor
      ~ClientSocket();
      
      // Simple send and receive methods
      bool Send(string strMsg);
      bool Send(uchar & callerBuffer[], int startAt = 0, int szToSend = -1);
      string Receive(string MessageSeparator = "");
      int Receive(uchar & callerBuffer[]);
      
      // State information
      bool IsSocketConnected() {return mConnected;}
      int GetLastSocketError() {return mLastWSAError;}
      ulong GetSocketHandle() {return (mSocket32 ? mSocket32 : mSocket64);}
      
      // Buffer sizes, overwriteable once the class has been created
      int ReceiveBufferSize;
      int SendBufferSize;
};


// -------------------------------------------------------------
// Constructor for a simple connection to 127.0.0.1
// -------------------------------------------------------------
ClientSocket::ClientSocket(ushort localport)
{
   // Default buffer sizes
   ReceiveBufferSize = 10000;
   SendBufferSize = 999999999;
   
   // Need to create either a 32-bit or 64-bit socket handle
   mConnected = false;
   mLastWSAError = 0;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      uint proto = IPPROTO_TCP;
      mSocket64 = socket(AF_INET, SOCK_STREAM, proto);
      if (mSocket64 == INVALID_SOCKET64) {
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("socket() failed, 64-bit, error: ", mLastWSAError);
         #endif
         return;
      }
   } else {
      int proto = IPPROTO_TCP;
      mSocket32 = socket(AF_INET, SOCK_STREAM, proto);
      if (mSocket32 == INVALID_SOCKET32) {
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("socket() failed, 32-bit, error: ", mLastWSAError);
         #endif
         return;
      }
   }
   
   // Fixed definition for connecting to 127.0.0.1, with variable port
   sockaddr server;
   server.family = AF_INET;
   server.port = htons(localport);
   server.address = 0x100007f; // 127.0.0.1
   
   // connect() call has to differ between 32-bit and 64-bit
   int res;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      res = connect(mSocket64, server, sizeof(sockaddr));
   } else {
      res = connect(mSocket32, server, sizeof(sockaddr));
   }
   if (res == SOCKET_ERROR) {
      // Ooops
      mLastWSAError = WSAGetLastError();
      #ifdef SOCKET_LIBRARY_LOGGING
         Print("connect() to localhost failed, error: ", mLastWSAError);
      #endif
      return;
   } else {
      mConnected = true;   
      
      // Set up event handling. Can fail if called in OnInit() when
      // MT4/5 is still loading, because no window handle is available
      #ifdef SOCKET_LIBRARY_USE_EVENTS
         SetupSocketEventHandling();
      #endif
   }
}

// -------------------------------------------------------------
// Constructor for connection to a hostname or IP address
// -------------------------------------------------------------

ClientSocket::ClientSocket(string HostnameOrIPAddress, ushort port)
{
   // Default buffer sizes
   ReceiveBufferSize = 10000;
   SendBufferSize = 999999999;

   // Need to create either a 32-bit or 64-bit socket handle
   mConnected = false;
   mLastWSAError = 0;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      uint proto = IPPROTO_TCP;
      mSocket64 = socket(AF_INET, SOCK_STREAM, proto);
      if (mSocket64 == INVALID_SOCKET64) {
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("socket() failed, 64-bit, error: ", mLastWSAError);
         #endif
         return;
      }
   } else {
      int proto = IPPROTO_TCP;
      mSocket32 = socket(AF_INET, SOCK_STREAM, proto);
      if (mSocket32 == INVALID_SOCKET32) {
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("socket() failed, 32-bit, error: ", mLastWSAError);
         #endif
         return;
      }
   }

   // Is the host parameter an IP address?
   uchar arrName[];
   StringToCharArray(HostnameOrIPAddress, arrName);
   ArrayResize(arrName, ArraySize(arrName) + 1);
   uint addr = inet_addr(arrName);
   
   if (addr == INADDR_NONE) {
      // Not an IP address. Need to look up the name
      // .......................................................................................
      // Unbelievably horrible handling of the hostent structure depending on whether
      // we're in 32-bit or 64-bit, with different-length memory pointers. 
      // Ultimately, we're having to deal here with extracting a uint** from
      // the memory block provided by Winsock - and with additional 
      // complications such as needing different versions of gethostbyname(),
      // because the return value is a pointer, which is 4 bytes in x86 and
      // 8 bytes in x64. So, we must artifically pass different types of buffer
      // to gethostbyname() depending on the environment, so that the compiler
      // doesn't treat them as imports which differ only by their return type.
      if (TerminalInfoInteger(TERMINAL_X64)) {
         char arrName64[];
         ArrayResize(arrName64, ArraySize(arrName));
         for (int i = 0; i < ArraySize(arrName); i++) arrName64[i] = (char)arrName[i];
         ulong nres = gethostbyname(arrName64);
         if (nres == 0) {
            // Name lookup failed
            mLastWSAError = WSAGetLastError();
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("Name-resolution in gethostbyname() failed, 64-bit, error: ", mLastWSAError);
            #endif
            return;
         } else {
            // Need to navigate the hostent structure. Very, very ugly...
            ushort addrlen;
            RtlMoveMemory(addrlen, nres + 18, 2);
            if (addrlen == 0) {
               // No addresses associated with name
               #ifdef SOCKET_LIBRARY_LOGGING
                  Print("Name-resolution in gethostbyname() returned no addresses, 64-bit, error: ", mLastWSAError);
               #endif
               return;
            } else {
               ulong ptr1, ptr2, ptr3;
               RtlMoveMemory(ptr1, nres + 24, 8);
               RtlMoveMemory(ptr2, ptr1, 8);
               RtlMoveMemory(ptr3, ptr2, 4);
               addr = (uint)ptr3;
            }
         }
      } else {
         uint nres = gethostbyname(arrName);
         if (nres == 0) {
            // Name lookup failed
            mLastWSAError = WSAGetLastError();
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("Name-resolution in gethostbyname() failed, 32-bit, error: ", mLastWSAError);
            #endif
            return;
         } else {
            // Need to navigate the hostent structure. Very, very ugly...
            ushort addrlen;
            RtlMoveMemory(addrlen, nres + 10, 2);
            if (addrlen == 0) {
               // No addresses associated with name
               #ifdef SOCKET_LIBRARY_LOGGING
                  Print("Name-resolution in gethostbyname() returned no addresses, 32-bit, error: ", mLastWSAError);
               #endif
               return;
            } else {
               int ptr1, ptr2;
               RtlMoveMemory(ptr1, nres + 12, 4);
               RtlMoveMemory(ptr2, ptr1, 4);
               RtlMoveMemory(addr, ptr2, 4);
            }
         }
      }
   
   } else {
      // The HostnameOrIPAddress parameter is an IP address,
      // which we have stored in addr
   }

   // Fill in the address and port into a sockaddr_in structure
   sockaddr server;
   server.family = AF_INET;
   server.port = htons(port);
   server.address = addr; // Already in network-byte-order

   // connect() call has to differ between 32-bit and 64-bit
   int res;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      res = connect(mSocket64, server, sizeof(sockaddr));
   } else {
      res = connect(mSocket32, server, sizeof(sockaddr));
   }
   if (res == SOCKET_ERROR) {
      // Ooops
      mLastWSAError = WSAGetLastError();
      #ifdef SOCKET_LIBRARY_LOGGING
         Print("connect() to server failed, error: ", mLastWSAError);
      #endif
   } else {
      mConnected = true;   

      // Set up event handling. Can fail if called in OnInit() when
      // MT4/5 is still loading, because no window handle is available
      #ifdef SOCKET_LIBRARY_USE_EVENTS
         SetupSocketEventHandling();
      #endif
   }
}

// -------------------------------------------------------------
// Constructors for internal use only, when accepting connections
// on a server socket
// -------------------------------------------------------------

ClientSocket::ClientSocket(ServerSocket* ForInternalUseOnly, SOCKET_HANDLE32 ForInternalUseOnly_clientsocket32)
{
   // Constructor ror "internal" use only, when accepting an incoming connection
   // on a server socket
   mConnected = true;
   ReceiveBufferSize = 10000;
   SendBufferSize = 999999999;

   mSocket32 = ForInternalUseOnly_clientsocket32;
}

ClientSocket::ClientSocket(ServerSocket* ForInternalUseOnly, SOCKET_HANDLE64 ForInternalUseOnly_clientsocket64)
{
   // Constructor ror "internal" use only, when accepting an incoming connection
   // on a server socket
   mConnected = true;
   ReceiveBufferSize = 10000;
   SendBufferSize = 999999999;

   mSocket64 = ForInternalUseOnly_clientsocket64;
}


// -------------------------------------------------------------
// Destructor. Close the socket if created
// -------------------------------------------------------------

ClientSocket::~ClientSocket()
{
   if (TerminalInfoInteger(TERMINAL_X64)) {
      if (mSocket64 != 0) {
         shutdown(mSocket64, 2);
         closesocket(mSocket64);
      }
   } else {
      if (mSocket32 != 0) {
         shutdown(mSocket32, 2);
         closesocket(mSocket32);
      }
   }   
}

// -------------------------------------------------------------
// Simple send function which takes a string parameter
// -------------------------------------------------------------

bool ClientSocket::Send(string strMsg)
{
   if (!mConnected) return false;

   // Make sure that event handling is set up, if requested
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      SetupSocketEventHandling();
   #endif 

   int szToSend = StringLen(strMsg);
   if (szToSend == 0) return true; // Ignore empty strings
      
   bool bRetval = true;
   uchar arr[];
   StringToCharArray(strMsg, arr);
   
   while (szToSend > 0) {
      int res, szAmountToSend = (szToSend > SendBufferSize ? SendBufferSize : szToSend);
      if (TerminalInfoInteger(TERMINAL_X64)) {
         res = send(mSocket64, arr, szToSend, 0);
      } else {
         res = send(mSocket32, arr, szToSend, 0);
      }
      
      if (res == SOCKET_ERROR || res == 0) {
         mLastWSAError = WSAGetLastError();
         if (mLastWSAError == WSAWOULDBLOCK) {
            // Blocking operation. Retry.
         } else {
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("send() failed, error: ", mLastWSAError);
            #endif

            // Assume death of socket for any other type of error
            szToSend = -1;
            bRetval = false;
            mConnected = false;
         }
      } else {
         szToSend -= res;
         if (szToSend > 0) {
            // If further data remains to be sent, shuffle the array downwards
            // by copying it onto itself. Note that the MQL4/5 documentation
            // says that the result of this is "undefined", but it seems
            // to work reliably in real life (because it almost certainly
            // just translates inside MT4/5 into a simple call to RtlMoveMemory,
            // which does allow overlapping source & destination).
            ArrayCopy(arr, arr, 0, res, szToSend);
         }
      }
   }

   return bRetval;
}

// -------------------------------------------------------------
// Simple send function which takes an array of uchar[], 
// instead of a string. Can optionally be given a start-index
// within the array (rather then default zero) and a number 
// of bytes to send.
// -------------------------------------------------------------

bool ClientSocket::Send(uchar & callerBuffer[], int startAt = 0, int szToSend = -1)
{
   if (!mConnected) return false;

   // Make sure that event handling is set up, if requested
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      SetupSocketEventHandling();
   #endif 

   // Process the start-at and send-size parameters
   int arraySize = ArraySize(callerBuffer);
   if (!arraySize) return true; // Ignore empty arrays 
   if (startAt >= arraySize) return true; // Not a valid start point; nothing to send
   if (szToSend <= 0) szToSend = arraySize;
   if (startAt + szToSend > arraySize) szToSend = arraySize - startAt;
   
   // Take a copy of the array 
   uchar arr[];
   ArrayResize(arr, szToSend);
   ArrayCopy(arr, callerBuffer, 0, startAt, szToSend);   
      
   bool bRetval = true;
   
   while (szToSend > 0) {
      int res, szAmountToSend = (szToSend > SendBufferSize ? SendBufferSize : szToSend);
      if (TerminalInfoInteger(TERMINAL_X64)) {
         res = send(mSocket64, arr, szToSend, 0);
      } else {
         res = send(mSocket32, arr, szToSend, 0);
      }
      
      if (res == SOCKET_ERROR || res == 0) {
         mLastWSAError = WSAGetLastError();
         if (mLastWSAError == WSAWOULDBLOCK) {
            // Blocking operation. Retry.
         } else {
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("send() failed, error: ", mLastWSAError);
            #endif

            // Assume death of socket for any other type of error
            szToSend = -1;
            bRetval = false;
            mConnected = false;
         }
      } else {
         szToSend -= res;
         if (szToSend > 0) {
            // If further data remains to be sent, shuffle the array downwards
            // by copying it onto itself. Note that the MQL4/5 documentation
            // says that the result of this is "undefined", but it seems
            // to work reliably in real life (because it almost certainly
            // just translates inside MT4/5 into a simple call to RtlMoveMemory,
            // which does allow overlapping source & destination).
            ArrayCopy(arr, arr, 0, res, szToSend);
         }
      }
   }

   return bRetval;
}


// -------------------------------------------------------------
// Simple receive function. Without a message separator,
// it simply returns all the data sitting on the socket.
// With a separator, it stores up incoming data until
// it sees the separator, and then returns the text minus
// the separator.
// Returns a blank string once no (more) data is waiting
// for collection.
// -------------------------------------------------------------

string ClientSocket::Receive(string MessageSeparator = "")
{
   if (!mConnected) return "";

   // Make sure that event handling is set up, if requested
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      SetupSocketEventHandling();
   #endif
   
   string strRetval = "";
   
   uchar arrBuffer[];
   ArrayResize(arrBuffer, ReceiveBufferSize);

   uint nonblock = 1;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      ioctlsocket(mSocket64, FIONBIO, nonblock);
 
      int res = 1;
      while (res > 0) {
         res = recv(mSocket64, arrBuffer, ReceiveBufferSize, 0);
         if (res > 0) {
            StringAdd(mPendingReceiveData, CharArrayToString(arrBuffer, 0, res));

         } else if (res == 0) {
            // No data

         } else {
            mLastWSAError = WSAGetLastError();

            if (mLastWSAError != WSAWOULDBLOCK) {
               #ifdef SOCKET_LIBRARY_LOGGING
                  Print("recv() failed, result:, " , res, ", error: ", mLastWSAError, " queued bytes: " , StringLen(mPendingReceiveData));
               #endif
               mConnected = false;
            }
         }
      }
   } else {
      ioctlsocket(mSocket32, FIONBIO, nonblock);

      int res = 1;
      while (res > 0) {
         res = recv(mSocket32, arrBuffer, ReceiveBufferSize, 0);
         if (res > 0) {
            StringAdd(mPendingReceiveData, CharArrayToString(arrBuffer, 0, res));

         } else if (res == 0) {
            // No data
         
         } else {
            mLastWSAError = WSAGetLastError();

            if (mLastWSAError != WSAWOULDBLOCK) {
               #ifdef SOCKET_LIBRARY_LOGGING
                  Print("recv() failed, result:, " , res, ", error: ", mLastWSAError, " queued bytes: " , StringLen(mPendingReceiveData));
               #endif
               mConnected = false;
            }
         }
      }
   }   
   
   if (mPendingReceiveData == "") {
      // No data
      
   } else if (MessageSeparator == "") {
      // No requested message separator to wait for
      strRetval = mPendingReceiveData;
      mPendingReceiveData = "";
   
   } else {
      int idx = StringFind(mPendingReceiveData, MessageSeparator);
      if (idx >= 0) {
         while (idx == 0) {
            mPendingReceiveData = StringSubstr(mPendingReceiveData, idx + StringLen(MessageSeparator));
            idx = StringFind(mPendingReceiveData, MessageSeparator);
         }
         
         strRetval = StringSubstr(mPendingReceiveData, 0, idx);
         mPendingReceiveData = StringSubstr(mPendingReceiveData, idx + StringLen(MessageSeparator));
      }
   }
   
   return strRetval;
}

// -------------------------------------------------------------
// Receive function which fills an array, provided by reference.
// Always clears the array. Returns the number of bytes 
// put into the array.
// If you send and receive binary data, then you can no longer 
// use the built-in messaging protocol provided by this library's
// option to process a message terminator such as \r\n. You have
// to implement the messaging yourself.
// -------------------------------------------------------------

int ClientSocket::Receive(uchar & callerBuffer[])
{
   if (!mConnected) return 0;

   ArrayResize(callerBuffer, 0);
   int ctTotalReceived = 0;
   
   // Make sure that event handling is set up, if requested
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      SetupSocketEventHandling();
   #endif
   
   uchar arrBuffer[];
   ArrayResize(arrBuffer, ReceiveBufferSize);

   uint nonblock = 1;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      ioctlsocket(mSocket64, FIONBIO, nonblock);
   } else {
      ioctlsocket(mSocket32, FIONBIO, nonblock);
   }

   int res = 1;
   while (res > 0) {
      if (TerminalInfoInteger(TERMINAL_X64)) {
         res = recv(mSocket64, arrBuffer, ReceiveBufferSize, 0);
      } else {
         res = recv(mSocket32, arrBuffer, ReceiveBufferSize, 0);
      }
      
      if (res > 0) {
         ArrayResize(callerBuffer, ctTotalReceived + res);
         ArrayCopy(callerBuffer, arrBuffer, ctTotalReceived, 0, res);
         ctTotalReceived += res;

      } else if (res == 0) {
         // No data

      } else {
         mLastWSAError = WSAGetLastError();

         if (mLastWSAError != WSAWOULDBLOCK) {
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("recv() failed, result:, " , res, ", error: ", mLastWSAError);
            #endif
            mConnected = false;
         }
      }
   }
   
   return ctTotalReceived;
}

// -------------------------------------------------------------
// Event handling in client socket
// -------------------------------------------------------------

void ClientSocket::SetupSocketEventHandling()
{
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      if (mDoneEventHandling) return;
      
      // Can only do event handling in an EA. Ignore otherwise.
      if (MQLInfoInteger(MQL_PROGRAM_TYPE) != PROGRAM_EXPERT) {
         mDoneEventHandling = true;
         return;
      }
      
      long hWnd = ChartGetInteger(0, CHART_WINDOW_HANDLE);
      if (!hWnd) return;
      mDoneEventHandling = true; // Don't actually care whether it succeeds.
      
      if (TerminalInfoInteger(TERMINAL_X64)) {
         WSAAsyncSelect(mSocket64, hWnd, 0x100 /* WM_KEYDOWN */, 0xFF /* All events */);
      } else {
         WSAAsyncSelect(mSocket32, (int)hWnd, 0x100 /* WM_KEYDOWN */, 0xFF /* All events */);
      }
   #endif
}


// -------------------------------------------------------------
// Server socket class
// -------------------------------------------------------------

class ServerSocket
{
   private:
      // Need different socket handles for 32-bit and 64-bit environments
      SOCKET_HANDLE32 mSocket32;
      SOCKET_HANDLE64 mSocket64;

      // Other state variables
      bool mCreated;
      int mLastWSAError;
      
      // Optional event handling
      void SetupSocketEventHandling();
      bool mDoneEventHandling;
                 
   public:
      // Constructor, specifying whether we allow remote connections
      ServerSocket(ushort ServerPort, bool ForLocalhostOnly);
      
      // Destructor
      ~ServerSocket();
      
      // Accept function, which returns NULL if no waiting client, or
      // a new instace of ClientSocket()
      ClientSocket * Accept();

      // Access to state information
      bool Created() {return mCreated;}
      int GetLastSocketError() {return mLastWSAError;}
      ulong GetSocketHandle() {return (mSocket32 ? mSocket32 : mSocket64);}
};


// -------------------------------------------------------------
// Constructor for server socket
// -------------------------------------------------------------

ServerSocket::ServerSocket(ushort serverport, bool ForLocalhostOnly)
{
   // Create socket and make it non-blocking
   mCreated = false;
   mLastWSAError = 0;
   if (TerminalInfoInteger(TERMINAL_X64)) {
      // Force compiler to use the 64-bit version of socket() 
      // by passing it a uint 3rd parameter 
      uint proto = IPPROTO_TCP;
      mSocket64 = socket(AF_INET, SOCK_STREAM, proto);
      
      if (mSocket64 == INVALID_SOCKET64) {
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("socket() failed, 64-bit, error: ", mLastWSAError);
         #endif
         return;
      }
      uint nonblock = 1;
      ioctlsocket(mSocket64, FIONBIO, nonblock);

   } else {
      // Force compiler to use the 32-bit version of socket() 
      // by passing it a int 3rd parameter 
      int proto = IPPROTO_TCP;
      mSocket32 = socket(AF_INET, SOCK_STREAM, proto);
      
      if (mSocket32 == INVALID_SOCKET32) {
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("socket() failed, 32-bit, error: ", mLastWSAError);
         #endif
         return;
      }
      uint nonblock = 1;
      ioctlsocket(mSocket32, FIONBIO, nonblock);
   }

   // Try a bind
   sockaddr server;
   server.family = AF_INET;
   server.port = htons(serverport);
   server.address = (ForLocalhostOnly ? 0x100007f : 0); // 127.0.0.1 or INADDR_ANY

   if (TerminalInfoInteger(TERMINAL_X64)) {
      int bindres = bind(mSocket64, server, sizeof(sockaddr));
      if (bindres != 0) {
         // Bind failed
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("bind() failed, 64-bit, port probably already in use, error: ", mLastWSAError);
         #endif
         return;
         
      } else {
         int listenres = listen(mSocket64, 10);
         if (listenres != 0) {
            // Listen failed
            mLastWSAError = WSAGetLastError();
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("listen() failed, 64-bit, error: ", mLastWSAError);
            #endif
            return;
            
         } else {
            mCreated = true;         
         }
      }
   } else {
      int bindres = bind(mSocket32, server, sizeof(sockaddr));
      if (bindres != 0) {
         // Bind failed
         mLastWSAError = WSAGetLastError();
         #ifdef SOCKET_LIBRARY_LOGGING
            Print("bind() failed, 32-bit, port probably already in use, error: ", mLastWSAError);
         #endif
         return;
         
      } else {
         int listenres = listen(mSocket32, 10);
         if (listenres != 0) {
            // Listen failed
            mLastWSAError = WSAGetLastError();
            #ifdef SOCKET_LIBRARY_LOGGING
               Print("listen() failed, 32-bit, error: ", mLastWSAError);
            #endif
            return;
            
         } else {
            mCreated = true;         
         }
      }
   }
   
   // Try settig up event handling; can fail here in constructor
   // if no window handle is available because it's being called 
   // from OnInit() while MT4/5 is loading
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      SetupSocketEventHandling();
   #endif
}


// -------------------------------------------------------------
// Destructor. Close the socket if created
// -------------------------------------------------------------

ServerSocket::~ServerSocket()
{
   if (TerminalInfoInteger(TERMINAL_X64)) {
      if (mSocket64 != 0)  closesocket(mSocket64);
   } else {
      if (mSocket32 != 0)  closesocket(mSocket32);
   }   
}

// -------------------------------------------------------------
// Accepts any incoming connection. Returns either NULL,
// or an instance of ClientSocket
// -------------------------------------------------------------

ClientSocket * ServerSocket::Accept()
{
   if (!mCreated) return NULL;
   
   // Make sure that event handling is in place; can fail in constructor
   // if no window handle is available because it's being called 
   // from OnInit() while MT4/5 is loading
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      SetupSocketEventHandling();
   #endif
   
   ClientSocket * pClient = NULL;

   if (TerminalInfoInteger(TERMINAL_X64)) {
      SOCKET_HANDLE64 acc = accept(mSocket64, 0, 0);
      if (acc != INVALID_SOCKET64) {
         pClient = new ClientSocket(NULL, acc);
      }
   } else {
      SOCKET_HANDLE32 acc = accept(mSocket32, 0, 0);
      if (acc != INVALID_SOCKET32) {
         pClient = new ClientSocket(NULL, acc);
      }
   }

   return pClient;
}

// -------------------------------------------------------------
// Event handling
// -------------------------------------------------------------

void ServerSocket::SetupSocketEventHandling()
{
   #ifdef SOCKET_LIBRARY_USE_EVENTS
      if (mDoneEventHandling) return;
   
      // Can only do event handling in an EA. Ignore otherwise.
      if (MQLInfoInteger(MQL_PROGRAM_TYPE) != PROGRAM_EXPERT) {
         mDoneEventHandling = true;
         return;
      }
    
      long hWnd = ChartGetInteger(0, CHART_WINDOW_HANDLE);
      if (!hWnd) return;
      mDoneEventHandling = true; // Don't actually care whether it succeeds.
      
      if (TerminalInfoInteger(TERMINAL_X64)) {
         WSAAsyncSelect(mSocket64, hWnd, 0x100 /* WM_KEYDOWN */, 0xFF /* All events */);
      } else {
         WSAAsyncSelect(mSocket32, (int)hWnd, 0x100 /* WM_KEYDOWN */, 0xFF /* All events */);
      }
   #endif
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//#include <MT5_Socket_Lib.mqh>
//#include <MT5_Socket_Functions_V1.02.mqh>
#include <Trade\Trade.mqh>          // include the library for execution of trades
#include <Trade\PositionInfo.mqh>   // include the library for obtaining information on positions
#include <Trade\OrderInfo.mqh>      // include the library for obtaining order information
#include <Trade\DealInfo.mqh>       // include the library for obtaining deal information
#include <Trade\SymbolInfo.mqh>     // include the library for obtaining information on symbol

#include <Trade\TerminalInfo.mqh>   // include the library for obtaining information on terminal
#include <Trade\AccountInfo.mqh>   // include the library for obtaining information on terminal


CTrade _trade;
CPositionInfo _positionInfo;
CSymbolInfo _symbolInfo;
COrderInfo _orderInfo;
CDealInfo _dealInfo;
CTerminalInfo  _terminal;
CAccountInfo _account;

struct _openOrder
{
   bool OK;
   ulong ticket;
   ulong position_order_id;
   string message;
   uint resultCode;
};

struct _deal_Info{
   long     ticket;
   long     positionTicket;
   long     orderTicket;
   long     magicNumber;
   int      type;
   int      entry;
   string   comment;
   string   symbol;
   double   volume;
   double   price;
   double   swap;
   double   commission;
   double   profit;
   int      time;
};

struct position_info{

   long ticket;
   long orderTicket;
   long magicNumber;
   double openPrice;
   double closePrice;
   int openDate;
   double volume;
   double swap;
   double commission;
   int closeDate;
   double profit;
   string symbol;
   string comment;
   int type;

};

MqlTick arrayTicks[];

// -------------------------------------------------------------
// Forward definitions of classes
// -------------------------------------------------------------

class MT5_F000;                           // check for connection
class MT5_F001;                           // get static account info
class MT5_F002;                           // get dynamic account info
class MT5_F003;                           // get symbol info
class MT5_F004;                           // check fot instrument excistence

class MT5_F005;                           // get server time
class MT5_F007;                           // get symbol list

class MT5_F020;                           // get tick info

class MT5_F030;                           // get instrument market info
class MT5_F040;                           // get x bars from now
class MT5_F041;                           // get actual bar info

class MT5_F060;                           // get market orders
class MT5_F061;                           // get market positions

class MT5_F070;                           // place order
class MT5_F071;                           // close position by ticket
class MT5_F073;                           // delete order by ticket
class MT5_F075;                           // update sl & tp for position
class MT5_F076;                           // update sl & tp for order

class MT5_F000							         // check for connection
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F000();

      // Destructor
      ~MT5_F000();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F000, symbol rates
// -------------------------------------------------------------
MT5_F000::MT5_F000()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F000::~MT5_F000()
{
   
}

string MT5_F000::Execute(string command)
{
   string returnString = "";
   
   returnString = "F000#OK#!";
   
   return returnString;
   
}


class MT5_F001
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F001();

      // Destructor
      ~MT5_F001();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F001, static account info
// -------------------------------------------------------------
MT5_F001::MT5_F001()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F001::~MT5_F001()
{
   
}

string MT5_F001::Execute(string command)
{
   string returnString = "";
   string split[];
      
   StringSplit(command,char('#'), split);

   returnString = "F001#9#";
   
   returnString = returnString + AccountInfoString(ACCOUNT_NAME) + "#";
   returnString = returnString + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "#";
   returnString = returnString + AccountInfoString(ACCOUNT_CURRENCY) + "#";
   if (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) {
      returnString = returnString + "demo#";
   } else if (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) {
      returnString = returnString + "real#";
   } else {
      returnString = returnString + "Unknown";
   }
   
   returnString = returnString + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)) + "#";
   returnString = returnString + IntegerToString(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) + "#";
   returnString = returnString + IntegerToString(AccountInfoInteger(ACCOUNT_LIMIT_ORDERS)) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL)) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 2) + "#!";
   
   return returnString;
}

class MT5_F002
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F002();

      // Destructor
      ~MT5_F002();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F002, dynamic account info
// -------------------------------------------------------------
MT5_F002::MT5_F002()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------

MT5_F002::~MT5_F002()
{
   
}

string MT5_F002::Execute(string command)
{
   string returnString = "";
   string split[];
      
   StringSplit(command,char('#'), split);

   returnString = "F002#6#";
  
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + "#";
   returnString = returnString + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "#!";
   
   return returnString;
}

class MT5_F003
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F003();

      // Destructor
      ~MT5_F003();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F003, Instrument info
// -------------------------------------------------------------
MT5_F003::MT5_F003()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F003::~MT5_F003()
{
   
}

string MT5_F003::Execute(string command)
{
   string returnString = "";
   string split[];
   
   
   StringSplit(command,char('#'), split);
   string _symbol = split[2];
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();

   if (_symbolInfo.Ask() <= 0.0){
      return "F998#2#Not known instrument#0#!";
   }
   
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }

   returnString = "F003#7#";
   
   returnString = returnString + IntegerToString(_symbolInfo.Digits()) + "#";
   returnString = returnString + DoubleToString(_symbolInfo.LotsMax(), 2) + "#";
   returnString = returnString + DoubleToString(_symbolInfo.LotsMin(), 2) + "#";
   returnString = returnString + DoubleToString(_symbolInfo.LotsStep(), 2) + "#";
   returnString = returnString + DoubleToString(_symbolInfo.Point(), 5) + "#";
   returnString = returnString + DoubleToString(_symbolInfo.TickSize(), 5) + "#";
   returnString = returnString + DoubleToString(_symbolInfo.TickValue(), 5) + "#!";
   
   return returnString;
}

class MT5_F004
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F004();

      // Destructor
      ~MT5_F004();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F004, symbol rates
// -------------------------------------------------------------
MT5_F004::MT5_F004()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F004::~MT5_F004()
{
   
}

string MT5_F004::Execute(string command)
{
   string returnString = "";
   string split[];
     
   StringSplit(command,char('#'), split);
   string _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }   
   
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   


   returnString = "F004#";
   
   if (_symbolInfo.Ask() > 0.0)
   {
      returnString = "F004#1#OK#!";
   }
   else
   {
      returnString = "F004#1#Not known#!";
   }
      
   return returnString;
}

class MT5_F005                                                       // get broker server time
{
   private:
      
      // Other state variables
      MqlDateTime serverTime;
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F005();

      // Destructor
      ~MT5_F005();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F005, server time
// -------------------------------------------------------------
MT5_F005::MT5_F005()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F005::~MT5_F005()
{
   
}

string MT5_F005::Execute(string command)
{
   string returnString = "";
   string split[];
   datetime now;
  
   
   now = TimeCurrent(serverTime);
   
   returnString = "F005#1#";
   returnString = returnString + IntegerToString(serverTime.year) + "-" + IntegerToString(serverTime.mon) + "-"  + IntegerToString(serverTime.day) + "-"; 
   returnString = returnString + IntegerToString(serverTime.hour) + "-" + IntegerToString(serverTime.min) + "-"  + IntegerToString(serverTime.sec); 
   returnString = returnString + "#!";
   
   return returnString;
}

class MT5_F007                                                      // get broker market symbol list
{
   private:
      
      // Other state variables
      //MqlDateTime serverTime;
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F007();

      // Destructor
      ~MT5_F007();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F004, symbol rates
// -------------------------------------------------------------
MT5_F007::MT5_F007()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F007::~MT5_F007()
{
   
}

string MT5_F007::Execute(string command)
{
   string returnString = "";
   string split[];
   datetime now;
   bool bMarket = true;
   int iNbrOfSymbols = 0;
   
   StringSplit(command,char('#'), split);
   if ((int)StrToNumber(split[1]) == 0) bMarket = false;
   
   iNbrOfSymbols = SymbolsTotal(bMarket);
   
   returnString = "F007#" + IntegerToString(iNbrOfSymbols) + "#";
   
   for( int u = 0; u < iNbrOfSymbols; u++) {
      returnString = returnString + SymbolName(u, bMarket) + "#";
   }
   
   returnString = returnString + "!";    
   return returnString;
}

class MT5_F020                                                       // get last tick info
{
   private:
      
      // Other state variables

      MqlTick last_tick;
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F020();

      // Destructor
      ~MT5_F020();
      
      // Simple send and receive methods
      string Execute(string command);
      

};

// -------------------------------------------------------------
// Constructor for a F020, symbol rates
// -------------------------------------------------------------
MT5_F020::MT5_F020()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F020::~MT5_F020()
{
   
}

string MT5_F020::Execute(string command)
{
   string returnString = "";
   string split[];
   
   StringSplit(command,char('#'), split);
   string _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }
   
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   ResetLastError();
   
   if(SymbolInfoTick(_symbolInfo.Name(), last_tick)) {
      returnString = "F020#5#" + IntegerToString(last_tick.time) + "#" + DoubleToString(last_tick.ask,6) + "#" + DoubleToString(last_tick.bid,6) + "#" ;
      returnString = returnString + DoubleToString(last_tick.last,6) + "#" + IntegerToString(last_tick.volume) + "#!";
   }
   else {
      returnString = "F998#2#" + IntegerToString(GetLastError()) + "#0#!";
   }  

   return returnString;
}

class MT5_F021                                                       // get last x ticks from now
{
   private:
      
      // Other state variables

      MqlTick last_tick;
      MqlTick array[];
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F021();

      // Destructor
      ~MT5_F021();
      
      // Simple send and receive methods
      string Execute(string command);
      

};

// -------------------------------------------------------------
// Constructor for a F020, symbol rates
// -------------------------------------------------------------
MT5_F021::MT5_F021()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F021::~MT5_F021()
{
   
}

string MT5_F021::Execute(string command)
{
   string returnString = "";
   string _symbol = "";
   string split[];
   int nbrOfTicks=0;
   int _digits = 5;
   int iBegin = 0;
   int iNbrOfRecords = 0;
      
   StringSplit(command,char('#'), split);
   _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   _digits = _symbolInfo.Digits();
   iBegin = (int)StrToNumber(split[3]);
   nbrOfTicks = (int)StrToNumber(split[4]);
   
   ArrayResize(array, nbrOfTicks);
   ResetLastError();
   iNbrOfRecords = CopyTicks(_symbolInfo.Name(), array, COPY_TICKS_ALL, iBegin, nbrOfTicks);
   
   if (iNbrOfRecords == -1) {
      returnString = "F998#2#Error, no records, " + IntegerToString(GetLastError()) + "#0#!";
      return returnString;
   }
   
   returnString = "F021#" + IntegerToString(iNbrOfRecords) + "#";
   for (int u = 0; u < iNbrOfRecords; u++) {
      returnString = returnString + IntegerToString(array[u].time) + "$" + DoubleToString(array[u].ask,_digits) + "$" 
                        + DoubleToString(array[u].bid,_digits) + "$" + DoubleToString(array[u].last,_digits) + "$"
                        + IntegerToString(array[u].volume) + "#";
   }
   
   returnString = returnString + "!";

   return returnString;
}




class MT5_F041                                                       // get actual bar info
{
   private:
      
      // Other state variables
      MqlRates tmpRates[];
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F041();

      // Destructor
      ~MT5_F041();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F041, symbol rates
// -------------------------------------------------------------
MT5_F041::MT5_F041()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F041::~MT5_F041()
{
   
}

string MT5_F041::Execute(string command)
{
   string returnString = "";
   string _symbol;
   int timeFrame = 0;
   int nbrOfBars = 0;
   int _digits = 5;
   ENUM_TIMEFRAMES _timeFrame;
   string split[];
      
   StringSplit(command,char('#'), split);
   _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   _digits = _symbolInfo.Digits();
   timeFrame = (int)StrToNumber(split[3]);
   nbrOfBars = 1;
   _timeFrame = getTimeFrame(timeFrame);
   
   if (_timeFrame == -1) {
      return "F998#2#Wrong timeframe.#0#!";
   }
   
   ArrayResize(tmpRates, nbrOfBars);
   ResetLastError();
   int nbrOfRecords = CopyRates(_symbol, _timeFrame, 0, 1, tmpRates);
   if (nbrOfRecords == -1) {
      return "F998#2#Error no records selected by server# " + IntegerToString(GetLastError()) + "#" + _symbol + "#!";
   }
   else if (nbrOfRecords == 1) {
      returnString = "F041#" + IntegerToString(6) + "#";
      returnString = returnString + IntegerToString(tmpRates[0].time) + "#" + DoubleToString(tmpRates[0].open,_digits) + "#" 
                           + DoubleToString(tmpRates[0].high,_digits) + "#" + DoubleToString(tmpRates[0].low,_digits) + "#" + DoubleToString(tmpRates[0].close,_digits) + "#"
                           + IntegerToString(tmpRates[0].tick_volume) + "#";
      returnString = returnString + "!";
   }
   else {
      return "F998#2#Error#" + _symbol + "#!";
   }
   
   return returnString;
}


class MT5_F042                                                       // get last x bars from now
{
   private:
      
      // Other state variables
      MqlRates tmpRates[];
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F042();

      // Destructor
      ~MT5_F042();
      
      // Simple send and receive methods
      string Execute(string command);

};


// -------------------------------------------------------------
// Constructor for a F042, symbol rates
// -------------------------------------------------------------
MT5_F042::MT5_F042()
{
}
// -------------------------------------------------------------
// Destructor.
// -------------------------------------------------------------
MT5_F042::~MT5_F042()
{
}

string MT5_F042::Execute(string command)
{
   string returnString = "";
   string _symbol;
   int timeFrame = 0;
   int iNbrOfBars = 0;
   int iBegin = 0;
   int _digits = 5;
   ENUM_TIMEFRAMES _timeFrame;
   string split[];
   
   
   StringSplit(command,char('#'), split);
   _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#@#Instrument not in demo version#0#!";     
      }   
   }
   
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   _digits = _symbolInfo.Digits();
   timeFrame = (int)StrToNumber(split[3]);
   iBegin = (int)StrToNumber(split[4]);
   iNbrOfBars = (int)StrToNumber(split[5]);
   _timeFrame = getTimeFrame(timeFrame);
   if (_timeFrame == -1) {
      return "F998#2#Wrong timeframe.#0#!";
   }
   
   ArrayResize(tmpRates, iNbrOfBars);
   ResetLastError();
   int iNbrOfRecords = CopyRates(_symbol, _timeFrame, iBegin, iNbrOfBars, tmpRates);
   
   if (iNbrOfRecords == -1)  {
      return "F998#2#Error no records selected by server# " + IntegerToString(GetLastError()) + "#" + _symbol + "#!";
   }
   else {
      returnString = "F042#" + IntegerToString(iNbrOfRecords) + "#";
      for (int u = 0; u < iNbrOfRecords; u++) {
         returnString = returnString + IntegerToString(tmpRates[u].time) + "$" + DoubleToString(tmpRates[u].open,_digits) + "$" 
                           + DoubleToString(tmpRates[u].high,_digits) + "$" + DoubleToString(tmpRates[u].low,_digits) + "$" + DoubleToString(tmpRates[u].close,_digits) + "$"
                           + IntegerToString(tmpRates[u].tick_volume) + "#";
      }
      returnString = returnString + "!";
   }

   return returnString;
}

class MT5_F043                                                       // get last x bars from now
{
   private:
      
      // Other state variables
      MqlRates tmpRates[];
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F043();

      // Destructor
      ~MT5_F043();
      
      // Simple send and receive methods
      string Execute(string command);

};


// -------------------------------------------------------------
// Constructor for a F043, symbol rates
// -------------------------------------------------------------
MT5_F043::MT5_F043()
{
}
// -------------------------------------------------------------
// Destructor.
// -------------------------------------------------------------
MT5_F043::~MT5_F043()
{
}

string MT5_F043::Execute(string command)
{
   string returnString = "";
   string _symbol;
   int timeFrame = 0;
   int iNbrOfBars = 0;
   int iBegin = 0;
   int _digits = 5;
   ENUM_TIMEFRAMES _timeFrame;
   string split[];
      
   StringSplit(command,char('#'), split);
   _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   _digits = _symbolInfo.Digits();
   timeFrame = (int)StrToNumber(split[3]);
   iBegin = (int)StrToNumber(split[4]);
   iNbrOfBars = (int)StrToNumber(split[5]);
   _timeFrame = getTimeFrame(timeFrame);
   if (_timeFrame == -1) {
      return "F998#2#Wrong timeframe.#0#!";
   } 
   
   ArrayResize(tmpRates, iNbrOfBars);
   ResetLastError();
   int iNbrOfRecords = CopyRates(_symbol, _timeFrame, iBegin, iNbrOfBars, tmpRates);
   
   if (iNbrOfRecords == -1)  {
      return "F998#2#Error no records selected by server# " + IntegerToString(GetLastError()) + "#" + _symbol + "#!";
   }
   else {
      returnString = "F043#" + IntegerToString(iNbrOfRecords) + "#";
      for (int u = 0; u < iNbrOfRecords; u++) {
         returnString = returnString + IntegerToString(tmpRates[u].time) + "$" + DoubleToString(tmpRates[u].open,_digits) + "$" 
                           + DoubleToString(tmpRates[u].high,_digits) + "$" + DoubleToString(tmpRates[u].low,_digits) + "$" + DoubleToString(tmpRates[u].close,_digits) + "$"
                           + IntegerToString(tmpRates[u].tick_volume) + "#";
      }
      returnString = returnString + "!";
   }
   
   return returnString;
}

class MT5_F045                                                      // get specific bars for list of instruments
{
   private:
      
      // Other state variables
      MqlRates tmpRates[];
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F045();

      // Destructor
      ~MT5_F045();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F041, symbol rates
// -------------------------------------------------------------
MT5_F045::MT5_F045()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F045::~MT5_F045()
{
   
}

string MT5_F045::Execute(string command)
{
   
   //Print(command);
   string returnString = "";
   string _symbols;
   string _symbol = ";";
   int timeFrame = 0;
   int nbrOfBars = 0;
   int _digits = 5;
   int bar_index = 0;
   ENUM_TIMEFRAMES _timeFrame;
   string split[];
   string symbolSplit[];
      
   StringSplit(command,char('#'), split);
   _symbols = split[2];
   StringSplit(_symbols, char('$'), symbolSplit);
   //Print(symbolSplit[0]);
   bar_index = (int)StrToNumber(split[3]);
   timeFrame = (int)StrToNumber(split[4]);
   nbrOfBars = 2;
   _timeFrame = getTimeFrame(timeFrame);
   
   if (_timeFrame == -1) {
      return "F998#2#Wrong timeframe.#0#!";
   }   
   
   int iNbrOfSymbols = SymbolsTotal(true);
   for( int u = 0; u < iNbrOfSymbols; u++) {
      returnString = returnString + SymbolName(u, true) + "#";
   }  
   
   // check if all symbols are in marketwatch
   bool checkAll = true;
   bool checkSingle = false;
   for (int u = 0; u < ArraySize(symbolSplit)-1; u++) {
      _symbol = symbolSplit[u];
      checkSingle = false;
      for ( int uu = 0; uu < iNbrOfSymbols; uu++) {
         if (_symbol == SymbolName(uu, true)) {
            checkSingle = true;
            // check for demo
            if (bDemo) {
               if (checkInstrumentsInDemo(_symbol) == false) {
                  return "F998#2#Instrument not in demo version#0#!";     
               }   
            }
         }
      }
      if (checkSingle == false) {checkAll = false; break;}
   }
   
   if (checkAll == false) {
      returnString = "F998#2#Missing market symbols#0#!";
      return returnString;
   }
   
   ArrayResize(tmpRates, nbrOfBars);
   ResetLastError();
   
   returnString = "F045#" + IntegerToString(ArraySize(symbolSplit)-1) + "#";
   //Print(returnString);
   
   for (int u = 0; u < ArraySize(symbolSplit)-1; u++) {  
      _symbol = symbolSplit[u];
      _symbolInfo.Name(_symbol);
      _symbolInfo.RefreshRates();
      _digits = _symbolInfo.Digits();
      int nbrOfRecords = CopyRates(_symbol, _timeFrame, bar_index, 1, tmpRates);
      if (nbrOfRecords == -1) {
         return "F998#2#Error no records selected by server# " + IntegerToString(GetLastError()) + "#" + _symbol + "#!";
      }
      else if (nbrOfRecords == 1) {
      
         returnString = returnString + _symbol + "$";
         returnString = returnString + IntegerToString(tmpRates[0].time) + "$" + DoubleToString(tmpRates[0].open,_digits) + "$" 
                              + DoubleToString(tmpRates[0].high,_digits) + "$" + DoubleToString(tmpRates[0].low,_digits) + "$" 
                              + DoubleToString(tmpRates[0].close,_digits) + "$"
                              + IntegerToString(tmpRates[0].tick_volume) + "#";
      }      
   }
   //Print(returnString);
   returnString = returnString + "!"; 
   return returnString;
}


class MT5_F060                                                       // get all orders
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F060();

      // Destructor
      ~MT5_F060();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F060, symbol rates
// -------------------------------------------------------------
MT5_F060::MT5_F060()
{

}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F060::~MT5_F060()
{
   
}

string MT5_F060::Execute(string command)
{
   string returnString = "";
   string _comment = "";
   
   int nbrOfOrders = OrdersTotal();
   if (nbrOfOrders == 0) {
      returnString = "F060#0#!";
      return returnString;
   }
   returnString = "F060#" + IntegerToString(nbrOfOrders) + "#";
   
   for (int u = nbrOfOrders-1; u >= 0; u--) {
      ulong    orderTicket          = OrderGetTicket(u);
      long     orderType            = OrderGetInteger(ORDER_TYPE);
      string   orderSymbol          = OrderGetString(ORDER_SYMBOL);
      long     orderMagic           = OrderGetInteger(ORDER_MAGIC);
      double   orderLots            = OrderGetDouble(ORDER_VOLUME_INITIAL);
      double   orderSL              = OrderGetDouble(ORDER_SL);
      double   orderTP              = OrderGetDouble(ORDER_TP);
      double   orderOpenPrice       = OrderGetDouble(ORDER_PRICE_OPEN);
      string   orderComment         = OrderGetString(ORDER_COMMENT);
      
      returnString = returnString + IntegerToString(orderTicket) + "$" + orderSymbol + "$" ;
      if (orderType == ORDER_TYPE_BUY) returnString = returnString + "buy$";
      else if (orderType == ORDER_TYPE_SELL) returnString = returnString + "sell$";
      else if (orderType == ORDER_TYPE_BUY_STOP) returnString = returnString + "buy_stop$";
      else if (orderType == ORDER_TYPE_SELL_STOP) returnString = returnString + "sell_stop$";
      else if (orderType == ORDER_TYPE_BUY_LIMIT) returnString = returnString + "buy_limit$";
      else if (orderType == ORDER_TYPE_SELL_LIMIT) returnString = returnString + "sell_limit$";
      else returnString = returnString + "unknown,";
      _comment = filterComment(orderComment);
      //_comment = orderComment;

      returnString = returnString + IntegerToString(orderMagic) + "$" + DoubleToString(orderLots, 5) + "$" + DoubleToString(orderOpenPrice, 5) + "$";
      returnString = returnString + DoubleToString(orderSL, 5) + "$" + DoubleToString(orderTP, 5) + "$" + _comment + "#";
   }
   returnString = returnString + "!";
   
   return returnString;
}

class MT5_F061                                                       // get all open positions
{
   private:
      // Other state variables
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F061();

      // Destructor
      ~MT5_F061();
      
      // Simple send and receive methods
      string Execute(string command);
};

// -------------------------------------------------------------
// Constructor for a F061, symbol rates
// -------------------------------------------------------------
MT5_F061::MT5_F061()
{
}
// -------------------------------------------------------------
// Destructor.
// -------------------------------------------------------------
MT5_F061::~MT5_F061()
{
}

string MT5_F061::Execute(string command)
{
   string returnString = "";
   string _comment = "";
   double _commission;
   _deal_Info deals[];
   bool bCommission = true;
      
   int nbrOfPositions = PositionsTotal();
   if (nbrOfPositions == 0) {
      returnString = "F061#0#!";
      return returnString;
   }
   returnString = "F061#" + IntegerToString(nbrOfPositions) + "#";
   
   datetime firstDate = D'2050.01.01 00:00:00';
   
   // find firstDate
   datetime positionOpenTime = 0;
   for (int u = nbrOfPositions-1; u >= 0; u--) {
      ulong    positionTicket          = PositionGetTicket(u);
      datetime positionOpenTime        = PositionGetInteger(POSITION_TIME);
      if (positionOpenTime < firstDate) { firstDate = positionOpenTime; }
   }
   firstDate = firstDate - 24*60*60*5;
   Print(firstDate);
   HistorySelect(firstDate, TimeLocal());
   int nbrOfHistoricalDeals = HistoryDealsTotal();
   Print(nbrOfHistoricalDeals);
   if (nbrOfHistoricalDeals == 0) {bCommission = false;}
   ArrayResize(deals, nbrOfHistoricalDeals);
   
   int iCounter = 0;
   for (int u = 0;  u < nbrOfHistoricalDeals; u++){
      _dealInfo.SelectByIndex(u);
      if (_dealInfo.Time() < firstDate) continue;
      long     dealTicket              = _dealInfo.Ticket(); //HistoryDealGetTicket(u);
      int      dealType                = _dealInfo.DealType(); //HistoryDealGetInteger(DEAL_TYPE);
      int      dealEntry               = _dealInfo.Entry();
      string   dealSymbol              = _dealInfo.Symbol(); //HistoryDealGetString(DEAL_SYMBOL);
      string   dealComment             = _dealInfo.Comment(); //HistoryDealGetString(DEAL_COMMENT);
      long     dealMagic               = _dealInfo.Magic(); //HistoryDealGetInteger(DEAL_MAGIC);
      long     positionTicket          = _dealInfo.PositionId();
      long     orderTicket             = _dealInfo.Order();
      double   dealLots                = _dealInfo.Volume(); //HistoryDealGetDouble(DEAL_VOLUME);
      
      double   dealPrice               = _dealInfo.Price(); //HistoryDealGetDouble(DEAL_PRICE);
      double   dealProfit              = _dealInfo.Profit(); //HistoryDealGetDouble(DEAL_PROFIT);
      double   dealSwap                = _dealInfo.Swap(); //HistoryDealGetDouble(DEAL_SWAP);
      double   dealCommission          = _dealInfo.Commission(); //HistoryDealGetDouble(DEAL_COMMISSION);
      int      dealTime                = _dealInfo.Time(); //HistoryDealGetInteger(DEAL_TIME);
      
      deals[iCounter].ticket = dealTicket;
      deals[iCounter].type = dealType;
      deals[iCounter].entry = dealEntry;
      deals[iCounter].symbol = dealSymbol;
      deals[iCounter].comment = dealComment;
      deals[iCounter].magicNumber = dealMagic;
      deals[iCounter].positionTicket = positionTicket;
      deals[iCounter].orderTicket = orderTicket;
      deals[iCounter].volume = dealLots;
      deals[iCounter].price = dealPrice;
      deals[iCounter].profit = dealProfit;
      deals[iCounter].swap = dealSwap;
      deals[iCounter].commission = dealCommission;
      deals[iCounter].time = dealTime;
      iCounter++;
   }
   
   Print("iCounter: " + iCounter);
   
   for (int u = nbrOfPositions-1; u >= 0; u--) {
      ulong    positionTicket          = PositionGetTicket(u);
      long     positionType            = PositionGetInteger(POSITION_TYPE);
      string   positionSymbol          = PositionGetString(POSITION_SYMBOL);
      string   positionComment         = PositionGetString(POSITION_COMMENT);
      long     positionMagic           = PositionGetInteger(POSITION_MAGIC);
      double   positionLots            = PositionGetDouble(POSITION_VOLUME);
      double   positionSL              = PositionGetDouble(POSITION_SL);
      double   positionTP              = PositionGetDouble(POSITION_TP);
      double   positionOpenPrice       = PositionGetDouble(POSITION_PRICE_OPEN);
      double   positionProfit          = PositionGetDouble(POSITION_PROFIT);
      double   positionSwap            = PositionGetDouble(POSITION_SWAP);
      datetime positionOpenTime        = PositionGetInteger(POSITION_TIME);
      
      returnString = returnString + IntegerToString(positionTicket) + "$" + positionSymbol + "$" ;
      if (positionType == POSITION_TYPE_BUY) returnString = returnString + "buy$";
      else if (positionType == POSITION_TYPE_SELL) returnString = returnString + "sell$";
      else returnString = returnString + "unknown$";
      
      returnString = returnString + IntegerToString(positionMagic) + "$" + DoubleToString(positionLots, 5) + "$" + DoubleToString(positionOpenPrice, 5) + "$";
      returnString = returnString + IntegerToString(positionOpenTime) + "$" + DoubleToString(positionSL, 5) + "$" + DoubleToString(positionTP, 5);
      _comment = filterComment(positionComment);
      
      //Print("Position ticket: " + positionTicket);
      // find the commission
      _commission = 0.0;
      if (bCommission == true) {
         //Print("Here 1:");
         for (int z = 0; z < iCounter; z++) {
         
            //Print(" positionID :  " + IntegerToString(deals[z].positionTicket));
            if (deals[z].positionTicket = positionTicket) {
               _commission = deals[z].commission;
            }
         }
      }
      returnString = returnString + "$" + _comment + "$" + DoubleToString(positionProfit, 2) + "$" + DoubleToString(positionSwap,2) + "$" + DoubleToString(_commission,2)+ "#";
   }
   returnString = returnString + "!";
   
   return returnString;
}

class MT5_F062                                                       // get all closed positions
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F062();

      // Destructor
      ~MT5_F062();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F062, historical positions
// -------------------------------------------------------------
MT5_F062::MT5_F062()
{

}
// -------------------------------------------------------------
// Destructor.
// -------------------------------------------------------------
MT5_F062::~MT5_F062()
{
   
}

string MT5_F062::Execute(string command)
{
   string returnString = "";
   string split[];
   string split_2[];
   MqlDateTime begin;
   MqlDateTime end;
   _deal_Info deals[];
   datetime beginDate, endDate, selectDate;
   
   long positionTickets[];
   long testPositionTickets[];
         
   StringSplit(command, char('#'), split);
   // start date
   StringSplit(split[2], char('/'), split_2);
   begin.year = (int) StrToNumber(split_2[0]);
   if (begin.year < 2010) begin.year = 2010;
   begin.mon = (int) StrToNumber(split_2[1]);
   begin.day = (int) StrToNumber(split_2[2]);
   begin.hour = (int) StrToNumber(split_2[3]);
   begin.min = (int) StrToNumber(split_2[4]);
   begin.sec = (int) StrToNumber(split_2[5]);
   // end date
   StringSplit(split[3], char('/'), split_2);
   end.year = (int) StrToNumber(split_2[0]);
   end.mon = (int) StrToNumber(split_2[1]);
   end.day = (int) StrToNumber(split_2[2]);
   end.hour = (int) StrToNumber(split_2[3]);
   end.min = (int) StrToNumber(split_2[4]);
   end.sec = (int) StrToNumber(split_2[5]);
   
   if (StructToTime(end) < StructToTime(begin)) {
      returnString = "F998#2#Wrong period selection;#0#!";
      return returnString;
   }
   
   beginDate = StructToTime(begin);
   endDate = StructToTime(end);
   begin.year = begin.year - 2;
   HistorySelect(StructToTime(begin),StructToTime(end));
   selectDate = StructToTime(begin);
   int nbrOfHistoricalDeals = HistoryDealsTotal();
   
   if (nbrOfHistoricalDeals == 0)
   {
      returnString = "F062#0#!";
      return returnString;
   }
   
   ArrayResize(deals, nbrOfHistoricalDeals);
   int iCounter = 0;
   for (int u = 0;  u < nbrOfHistoricalDeals; u++)
   {
      _dealInfo.SelectByIndex(u);
      if (_dealInfo.Time() < selectDate) continue;
      long     dealTicket              = _dealInfo.Ticket(); //HistoryDealGetTicket(u);
      int      dealType                = _dealInfo.DealType(); //HistoryDealGetInteger(DEAL_TYPE);
      int      dealEntry               = _dealInfo.Entry();
      string   dealSymbol              = _dealInfo.Symbol(); //HistoryDealGetString(DEAL_SYMBOL);
      string   dealComment             = _dealInfo.Comment(); //HistoryDealGetString(DEAL_COMMENT);
      long     dealMagic               = _dealInfo.Magic(); //HistoryDealGetInteger(DEAL_MAGIC);
      long     positionTicket          = _dealInfo.PositionId();
      long     orderTicket             = _dealInfo.Order();
      double   dealLots                = _dealInfo.Volume(); //HistoryDealGetDouble(DEAL_VOLUME);
      
      double   dealPrice               = _dealInfo.Price(); //HistoryDealGetDouble(DEAL_PRICE);
      double   dealProfit              = _dealInfo.Profit(); //HistoryDealGetDouble(DEAL_PROFIT);
      double   dealSwap                = _dealInfo.Swap(); //HistoryDealGetDouble(DEAL_SWAP);
      double   dealCommission          = _dealInfo.Commission(); //HistoryDealGetDouble(DEAL_COMMISSION);
      int      dealTime                = _dealInfo.Time(); //HistoryDealGetInteger(DEAL_TIME);
      
      deals[iCounter].ticket = dealTicket;
      deals[iCounter].type = dealType;
      deals[iCounter].entry = dealEntry;
      deals[iCounter].symbol = dealSymbol;
      deals[iCounter].comment = dealComment;
      deals[iCounter].magicNumber = dealMagic;
      deals[iCounter].positionTicket = positionTicket;
      deals[iCounter].orderTicket = orderTicket;
      deals[iCounter].volume = dealLots;
      deals[iCounter].price = dealPrice;
      deals[iCounter].profit = dealProfit;
      deals[iCounter].swap = dealSwap;
      deals[iCounter].commission = dealCommission;
      deals[iCounter].time = dealTime;
      iCounter++;
   }
   // make a list of the out deals
   
   ArrayResize(testPositionTickets, 0);
   for ( int u = 0; u < iCounter; u++)
   {
      if (deals[u].entry == DEAL_ENTRY_OUT && deals[u].time >= beginDate) {
         ArrayResize(testPositionTickets, ArraySize(testPositionTickets) + 1);
         testPositionTickets[ArraySize(testPositionTickets)-1] = deals[u].positionTicket;
      }
   }
   
   position_info positions[];
   ArrayResize(positions, ArraySize(testPositionTickets));
   
   for (int u = 0; u < ArraySize(testPositionTickets); u++) {
      positions[u].commission = 0.0;
      for ( int uu = 0; uu < iCounter; uu++) {
         if (deals[uu].positionTicket == testPositionTickets[u] && deals[uu].entry == DEAL_ENTRY_OUT)
         {
            positions[u].closeDate = (int)deals[uu].time;
            positions[u].closePrice = deals[uu].price;
            positions[u].profit = deals[uu].profit;
            positions[u].commission = positions[u].commission + deals[uu].commission;
            positions[u].orderTicket = deals[uu].orderTicket;
            positions[u].swap = deals[uu].swap;
         }
         if (deals[uu].positionTicket == testPositionTickets[u] && deals[uu].entry == DEAL_ENTRY_IN)
         {
            positions[u].ticket = testPositionTickets[u];
            positions[u].openDate = (int)deals[uu].time;
            positions[u].openPrice = deals[uu].price;
            positions[u].comment = deals[uu].comment;
            positions[u].type = deals[uu].type;
            positions[u].symbol = deals[uu].symbol;
            positions[u].magicNumber = deals[uu].magicNumber;
            positions[u].volume = deals[uu].volume;
            positions[u].commission = positions[u].commission + deals[uu].commission;
         }
      }
   
   }
   
   // build return string
   returnString = "F062#" + IntegerToString(ArraySize(positions)) + "#";
   for (int u = 0; u < ArraySize(positions); u++){
      returnString = returnString + IntegerToString(positions[u].ticket) + "$" + positions[u].symbol + "$" + IntegerToString(positions[u].orderTicket) + "$";
      if (positions[u].type == DEAL_TYPE_BUY) { 
         returnString = returnString + "buy$";
      } else {
         returnString = returnString + "sell$";
      }
      returnString = returnString + IntegerToString(positions[u].magicNumber) + "$" + DoubleToString(positions[u].volume,2) + "$" + DoubleToString(positions[u].openPrice, 5) + "$";
      returnString = returnString + IntegerToString(positions[u].openDate) + "$" + DoubleToString(positions[u].closePrice, 5) + "$"  + IntegerToString(positions[u].closeDate) + "$";
      returnString = returnString + filterComment(positions[u].comment) + "$";
      returnString = returnString + DoubleToString(positions[u].profit,2) + "$" + DoubleToString(positions[u].swap,2) + "$" + DoubleToString(positions[u].commission,2) +"#";
   }
   
   returnString = returnString + "!";
   
   return returnString;
}

bool checkForNewPosition ( long &array[], long id)
{
   bool isNew = true;
   if (ArraySize(array) == 0 ) return true;
   for (int u = 0; u < ArraySize(array); u++) {
      if (array[u] == id) isNew = false;
   }

   return isNew;
}

class MT5_F070                                                       // open an order
{
   private:
      // Other state variables
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F070();

      // Destructor
      ~MT5_F070();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F070, 
// -------------------------------------------------------------
MT5_F070::MT5_F070()
{
}
// -------------------------------------------------------------
// Destructor.
// -------------------------------------------------------------
MT5_F070::~MT5_F070()
{
}

string MT5_F070::Execute(string command)
{
   string returnString = "";
   string split[];
   double orderVolume, orderOpenPrice, orderStopLoss, orderTakeProfit;
   string _symbol, orderComment;
   long orderMagicNumber;
   int orderSlippage = 0;
   _openOrder openOrder;
   ENUM_ORDER_TYPE orderType;
   
   // check for trades allowed
   if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      return "F998#2#Trading not allowed for terminal/or EA.#0#!";
   }
   
   StringSplit(command, char('#'), split);
   _symbol = split[2];
   // check for demo
   if (bDemo) {
      if (checkInstrumentsInDemo(_symbol) == false) {
         return "F998#2#Instrument not in demo version#0#!";     
      }   
   }
   _symbolInfo.Name(_symbol);
   _symbolInfo.RefreshRates();
   if (split[3] == "buy") orderType = ORDER_TYPE_BUY;
   else if (split[3] == "sell") orderType = ORDER_TYPE_SELL;
   else if (split[3] == "buy_stop") orderType = ORDER_TYPE_BUY_STOP;
   else if (split[3] == "sell_stop") orderType = ORDER_TYPE_SELL_STOP;
   else if (split[3] == "buy_limit") orderType = ORDER_TYPE_BUY_LIMIT;
   else if (split[3] == "sell_limit") orderType = ORDER_TYPE_SELL_LIMIT;
   else
   {
      // unknow order type
      returnString = "F998#2#Unknown order type.#0#!";
      return returnString;
   }
   orderVolume = StrToNumber(split[4]);
   orderOpenPrice = StrToNumber(split[5]);
   orderSlippage = (int)StrToNumber(split[6]);
   orderMagicNumber = (long)StrToNumber(split[7]);
   orderStopLoss = StrToNumber(split[8]);
   orderTakeProfit = StrToNumber(split[9]);
   orderComment = split[10];
   
   if (orderVolume > _symbolInfo.LotsMax() || orderVolume < _symbolInfo.LotsMin()) return "F998#2#Wrong volume.#0#!";
   
   if (orderType == ORDER_TYPE_BUY && orderStopLoss != 0.0)
   {
      if (orderStopLoss >= _symbolInfo.Ask()) return "F998#2#Wrong stop loss.#0#!";
   }
   if (orderType == ORDER_TYPE_BUY && orderTakeProfit != 0.0)
   {
      if (orderTakeProfit <= _symbolInfo.Ask()) return "F998#2#Wrong take profit.#0#!";
   }
   if (orderType == ORDER_TYPE_SELL && orderStopLoss != 0.0)
   {
      if (orderStopLoss <= _symbolInfo.Bid()) return "F998#2#Wrong stop loss.#0#!";
   }
   if (orderType == ORDER_TYPE_SELL && orderTakeProfit != 0.0)
   {
      if (orderTakeProfit >= _symbolInfo.Bid()) return "F998#2#Wrong take profit.#0#!";
   }
   
   if (orderType == ORDER_TYPE_BUY_STOP && (orderTakeProfit < orderOpenPrice && orderTakeProfit != 0.0)) return "F998#2#Wrong take profit.#0#!";
   if (orderType == ORDER_TYPE_BUY_STOP && (orderStopLoss > orderOpenPrice && orderStopLoss != 0.0)) return "F998#2#Wrong stop loss.#0#!";
   
   if (orderType == ORDER_TYPE_SELL_STOP && (orderTakeProfit > orderOpenPrice && orderTakeProfit != 0.0)) return "F998#2#Wrong take profit.#0#!";
   if (orderType == ORDER_TYPE_SELL_STOP && (orderStopLoss < orderOpenPrice && orderStopLoss != 0.0)) return "F998#2#Wrong take profit.#0#!";

   if (orderType == ORDER_TYPE_BUY_LIMIT && (orderTakeProfit < orderOpenPrice && orderTakeProfit != 0.0)) return "F998#2#Wrong take profit.#0#!";
   if (orderType == ORDER_TYPE_BUY_LIMIT && (orderStopLoss > orderOpenPrice && orderStopLoss != 0.0)) return "F998#2#Wrong stop loss.#0#!";
   
   if (orderType == ORDER_TYPE_SELL_LIMIT && (orderTakeProfit > orderOpenPrice && orderTakeProfit != 0.0)) return "F998#2#Wrong take profit.#0#!";
   if (orderType == ORDER_TYPE_SELL_LIMIT && (orderStopLoss < orderOpenPrice && orderStopLoss != 0.0)) return "F998#2#Wrong stop loss or take profit.#0#!";
   
   if (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL)
   {
      
      openOrder = trade(_symbolInfo.Name(), orderType, orderVolume, orderSlippage, orderStopLoss, orderTakeProfit, orderMagicNumber, orderComment);
      if (openOrder.OK)
      {
         returnString = "F070#2#" + IntegerToString(openOrder.ticket) + "#" + IntegerToString(openOrder.resultCode) + "#!";
      }
      else
      {
         returnString = "F998#2#" + openOrder.message + "#" + IntegerToString(openOrder.resultCode) + "#!";
      }
   }
   if (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_BUY_STOP 
               || orderType == ORDER_TYPE_SELL_STOP)
   {
      openOrder = openPendingOrder(_symbolInfo.Name(), orderType, orderVolume, orderOpenPrice, orderStopLoss, orderTakeProfit, orderMagicNumber);
      if (openOrder.ticket > 0) return "F070#2#" + IntegerToString(openOrder.ticket) + "#" + openOrder.message + "#!";
      if (openOrder.ticket < 0) return "F998#2#Error opening pending order.#" + openOrder.message + "#!";
   }
   
   return returnString;
}


class MT5_F071                         // --------------------------------------------------------close position by ticket
{
   private:
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F071();

      // Destructor
      ~MT5_F071();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F071, symbol rates
// -------------------------------------------------------------
MT5_F071::MT5_F071()
{
}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F071::~MT5_F071()
{
}

string MT5_F071::Execute(string command)
{
   string returnString;
   string split[];
   ulong ticket;  

   StringSplit(command, char('#'), split);
   ticket = (ulong)StrToNumber(split[2]);
   
   if(!_trade.PositionClose(ticket))
   {
      ::Print(__FUNCTION__,": > An error occurred when closing a position: ",::GetLastError());
      Print(_trade.ResultRetcode());
      returnString = "F988#2#Error in closing position.#" + IntegerToString(::GetLastError()) + "#!";
   }
   else
   {
      returnString = "F071#1#OK#!";
   }
   
   return returnString;
}

class MT5_F072                         // --------------------------------------------------------close position partly by ticket
{
   private:
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F072();

      // Destructor
      ~MT5_F072();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F071, symbol rates
// -------------------------------------------------------------
MT5_F072::MT5_F072()
{
}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------
MT5_F072::~MT5_F072()
{
}

string MT5_F072::Execute(string command)
{
   string returnString;
   string split[];
   ulong ticket;
   int _digits = 2;
   double volume_to_close = 0.0;
     
   StringSplit(command, char('#'), split);
   ticket = (ulong)StrToNumber(split[2]);
   volume_to_close = (float)StrToNumber(split[3]);
   
   // select the position
   bool OK = _positionInfo.SelectByTicket(ticket);
   if (OK == false){
      return "F988#2#Position does not exits.#" + IntegerToString(ticket) + "#!";
   }
   
   _symbolInfo.Name(_positionInfo.Symbol());
   _digits = _symbolInfo.Digits();
   
   double _volume = _positionInfo.Volume();

   if (volume_to_close < _symbolInfo.LotsMin()){
      volume_to_close = _symbolInfo.LotsMin();
   }
   if (volume_to_close > _symbolInfo.LotsMax()) return "F998#2#Wrong volume.#0#!";
   if (volume_to_close >= _volume) {return "F988#2#Wrong volume.#0#!";}
   // normalize volume
   double tmpValue = _symbolInfo.LotsStep();
   if (tmpValue >= 1.0) {_digits = 0;}
   if (tmpValue >= 0.1 && tmpValue < 1.0) {_digits = 1;}
   if (tmpValue == 0.01) {_digits = 2;}
   volume_to_close = NormalizeDouble(volume_to_close, _digits);
   Print("close 2: " + volume_to_close);
   
   //if(!_trade.PositionClose(ticket))
   if(!_trade.PositionClosePartial(ticket, volume_to_close))
   {
      ::Print(__FUNCTION__,": > An error occurred when closing a position: ",::GetLastError());
      Print(_trade.ResultRetcode());
      returnString = "F988#2#Error in partial closing position.#" + IntegerToString(::GetLastError()) + "#!";
   }
   else
   {
      returnString = "F072#1#OK#!";
   }
   
   return returnString;
}

class MT5_F073                                                       //  delete order by ticket
{
   private:
      
      // Other state variables
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F073();

      // Destructor
      ~MT5_F073();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F073, symbol rates
// -------------------------------------------------------------
MT5_F073::MT5_F073()
{
}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------

MT5_F073::~MT5_F073()
{
}

string MT5_F073::Execute(string command)
{
   string returnString;
   string split[];
   ulong ticket;
   
   StringSplit(command, char('#'), split);
   ticket = (ulong)StrToNumber(split[2]);
   
   if(!_trade.OrderDelete(ticket))
   {
      ::Print(__FUNCTION__,": > An error occurred when deleting an order: ",::GetLastError());
      Print(_trade.ResultRetcode());
      returnString = "F988#2#Error in deleting order.#" + IntegerToString(::GetLastError()) + "#!";
   }
   else
   {
      returnString = "F073#1#OK#!";
   }
   
   return returnString;
   
}

class MT5_F075                                                       // update sl & tp for position
{
   private:
      
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F075();

      // Destructor
      ~MT5_F075();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F073, symbol rates
// -------------------------------------------------------------
MT5_F075::MT5_F075()
{
}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------

MT5_F075::~MT5_F075()
{
}

string MT5_F075::Execute(string command)
{
   string returnString;
   string split[];
   ulong ticket;
   double sl, tp;
   ulong positionTicket;
      
   StringSplit(command, char('#'), split);
   ticket = (ulong)StrToNumber(split[2]);
   sl = StrToNumber(split[3]);
   tp = StrToNumber(split[4]);
   
   int nbrOfPositions = PositionsTotal();
   if (nbrOfPositions == 0) return "F998#2#No open positions#0#!";
   for (int u = 0; u < nbrOfPositions; u++)
   {
      positionTicket = PositionGetTicket(u);
      if (positionTicket == ticket)
      {
         _positionInfo.SelectByTicket(ticket);
         
         _symbolInfo.Name(_positionInfo.Symbol());
         _symbolInfo.RefreshRates();
         if (sl == 0.0) sl = _positionInfo.StopLoss();
         NormalizeDouble(sl, _symbolInfo.Digits()); 
         if (tp == 0.0) tp = _positionInfo.TakeProfit();
         NormalizeDouble(tp, _symbolInfo.Digits());
         if(!_trade.PositionModify(ticket, sl, tp))
         {
            ::Print(__FUNCTION__,": > An error occurred when modifying position: ",::GetLastError());
            Print(_trade.ResultRetcode());
            returnString = "F988#2#Error in modifying sl/tp.#" + IntegerToString(::GetLastError()) + "#!";
         }
         else
         {
            returnString = "F075#1#OK#!";
         }
      }
   }
   
   return returnString;
}

class MT5_F076                         // --------------------------------------------------------update sl & tp for order
{
   private:
      // Other state variables
      
   public:
      
      // Constructors for connecting to a server, either locally or remotely
      MT5_F076();

      // Destructor
      ~MT5_F076();
      
      // Simple send and receive methods
      string Execute(string command);

};

// -------------------------------------------------------------
// Constructor for a F073, symbol rates
// -------------------------------------------------------------
MT5_F076::MT5_F076()
{
}
// -------------------------------------------------------------
// Destructor. 
// -------------------------------------------------------------

MT5_F076::~MT5_F076()
{
}

string MT5_F076::Execute(string command)
{
   string returnString;
   string split[];
   ulong ticket;
   double sl, tp;
   ulong orderTicket;   

   StringSplit(command, char('#'), split);
   ticket = (int)StrToNumber(split[2]);
   sl = StrToNumber(split[3]);
   tp = StrToNumber(split[4]);
   
   int nbrOfOrders = OrdersTotal();
   if (nbrOfOrders == 0) return "F998#2#No open orders#0#!";
   for (int u = 0; u < nbrOfOrders; u++)
   {
      orderTicket = OrderGetTicket(u);
      if (orderTicket == ticket)
      {
         _orderInfo.Select(ticket);
         _symbolInfo.Name(_orderInfo.Symbol());
         _symbolInfo.RefreshRates();
         if (sl == 0.0) sl = _orderInfo.StopLoss();
         NormalizeDouble(sl, _symbolInfo.Digits());
         if (tp == 0.0) tp = _orderInfo.TakeProfit();
         NormalizeDouble(tp, _symbolInfo.Digits());
         if(!_trade.OrderModify(ticket, _orderInfo.PriceOpen(), sl, tp, _orderInfo.TypeTime(),0,0))
         {
            ::Print(__FUNCTION__,": > An error occurred when modifying position: ",::GetLastError());
            Print(_trade.ResultRetcode());
            returnString = "F988#2#Error in modifying sl/tp.#" + IntegerToString(::GetLastError()) + "#!";
         }
         else
         {
            returnString = "F076#1#OK#!";
         }
      }
   }
   
   return returnString;
}

//--------------------------------------------------------------------------------------------------------------------------------------------------

// supporting functions

_openOrder trade(string instrument, ENUM_ORDER_TYPE type, double volume, int slippage, double SL, double TP, int magicNumber, string comment)   
{    
   MqlTradeRequest request;
   MqlTradeResult  result;
   _openOrder _openResult;
   
   // OPEN TRADE AND RETURN POSITION TICKET
   ulong position_ticket, position_order_id;
   string position_symbol;
   double __volume;
   double position_openprice, position_lotsize;
   long position_magic, position_type;
   int waitCounter = 0;
   
   if (volume < SymbolInfoDouble(instrument, SYMBOL_VOLUME_MIN)) __volume = SymbolInfoDouble(instrument, SYMBOL_VOLUME_MIN);
   if (volume > SymbolInfoDouble(instrument, SYMBOL_VOLUME_MAX)) __volume = SymbolInfoDouble(instrument, SYMBOL_VOLUME_MAX);
   
   ZeroMemory(request);
   ZeroMemory(result);
   
   __volume = volume;
   request.action       = TRADE_ACTION_DEAL;               // type of trade operation
   request.symbol       = instrument;                      // instrument
   request.volume       = __volume;                        // volume
   request.deviation    = slippage;                        // allowed deviation from the price
   request.magic        = magicNumber;                     // MagicNumber of the order
   request.type_filling = GetFilling(request.symbol);
   request.comment      = comment;
   
   if(type == ORDER_TYPE_BUY)   
   { 
      request.type    = ORDER_TYPE_BUY; 
      request.price   = SymbolInfoDouble(instrument, SYMBOL_ASK);
      request.tp      = NormalizeDouble(TP, SymbolInfoInteger(instrument, SYMBOL_DIGITS));
      request.sl      = NormalizeDouble(SL, SymbolInfoInteger(instrument, SYMBOL_DIGITS));       
   };
   
   if(type == ORDER_TYPE_SELL)  { 
      request.type    = ORDER_TYPE_SELL; 
      request.price   = SymbolInfoDouble(instrument,SYMBOL_BID);
      request.tp      = NormalizeDouble(TP, SymbolInfoInteger(instrument, SYMBOL_DIGITS));
      request.sl      = NormalizeDouble(SL, SymbolInfoInteger(instrument, SYMBOL_DIGITS));
   };
   
   _openResult.OK = false;
   _openResult.ticket = 0;
   _openResult.position_order_id = 0;
   _openResult.message = "";
      
   waitCounter = 0;
   if(!OrderSend(request,result))   
   {
      PrintFormat("OrderSend error %d",GetLastError(), "Retcode = ", result.retcode);
      _openResult.OK = false;
      _openResult.message = orderReturnCode(result.retcode);
   }
   else
   {
      // wait for position
      while(result.retcode != TRADE_RETCODE_DONE) {  
         Sleep(20);
         waitCounter++;
         if (waitCounter > 10) {
            _openResult.OK = false;
            _openResult.message = orderReturnCode(result.retcode);
            _openResult.resultCode = result.retcode;
         }
      };
      int nbrOfPositions = PositionsTotal();
      
      for (int u = nbrOfPositions-1; u >= 0; u--) {
         position_ticket = ::PositionGetTicket(u);
         position_symbol = ::PositionGetString(POSITION_SYMBOL);
         position_magic = ::PositionGetInteger(POSITION_MAGIC);
         position_order_id = ::PositionGetInteger(POSITION_IDENTIFIER);
         
         if (position_order_id == result.order) {
            _openResult.OK = true;
            _openResult.ticket = position_ticket;
            _openResult.position_order_id = position_order_id;
            _openResult.resultCode = result.retcode;
            _openResult.message = orderReturnCode(result.retcode);
         }
      }   
   }
   return(_openResult);
}

_openOrder openPendingOrder( string instrument, ENUM_ORDER_TYPE type, double volume, double pendingPrice, double SL, double TP, long magicNumber)
{
   
   int waitCounter = 10;
   _openOrder openOrder;
   
   // normalize price and volume
   double _price = NormalizeDouble(pendingPrice, SymbolInfoInteger(instrument, SYMBOL_DIGITS));
   
   double _volume = volume;
   if (volume < SymbolInfoDouble(instrument, SYMBOL_VOLUME_MIN)) _volume = SymbolInfoDouble(instrument, SYMBOL_VOLUME_MIN);
   if (volume > SymbolInfoDouble(instrument, SYMBOL_VOLUME_MAX)) _volume = SymbolInfoDouble(instrument, SYMBOL_VOLUME_MAX);
   _volume = NormalizeDouble(_volume, 2);
   
   double tp = NormalizeDouble(TP, SymbolInfoInteger(instrument, SYMBOL_DIGITS));
   double sl = NormalizeDouble(SL, SymbolInfoInteger(instrument, SYMBOL_DIGITS));
   
   _trade.SetExpertMagicNumber(magicNumber);
   
   if (type == ORDER_TYPE_BUY_STOP)
   {
      bool OK = _trade.BuyStop(_volume, _price, instrument, sl, tp, ORDER_TIME_GTC, 0, NULL);
   }
   else if (type == ORDER_TYPE_SELL_STOP)
   {
      bool OK = _trade.SellStop(_volume, _price, instrument, sl, tp, ORDER_TIME_GTC, 0, NULL);
   }
   else if (type == ORDER_TYPE_BUY_LIMIT)
   {
      bool OK = _trade.BuyLimit(_volume, _price, instrument, sl, tp, ORDER_TIME_GTC, 0, NULL);
   }
   else if (type == ORDER_TYPE_SELL_LIMIT)
   {
      bool OK = _trade.SellLimit(_volume, _price, instrument, sl, tp, ORDER_TIME_GTC, 0, NULL);
   }
   
   openOrder.OK = false;
   openOrder.message = "";
   openOrder.ticket = 0;
      
   // check for result
   while (waitCounter > 0)
   {
      uint resultCode = _trade.ResultRetcode();
      if (resultCode == 10009)
      {
         Print("Open pending order with ticket: " + IntegerToString(_trade.ResultOrder()));
         
         openOrder.OK = true;
         openOrder.ticket = _trade.ResultOrder();
         openOrder.message = orderReturnCode(_trade.ResultRetcode());
         return openOrder;
      }
      else
      {
         waitCounter--;
         if (waitCounter < 0)
         {
            Print("Open pending order errorcode: " + IntegerToString(resultCode));
            openOrder.OK = false;
            openOrder.ticket = -1;
            openOrder.message = orderReturnCode(_trade.ResultRetcode());
            return openOrder;
         }
         Sleep(MathRand() / 10);
      }
   }
   
   return openOrder;
}


ENUM_TIMEFRAMES getTimeFrame(int frame)
{
   if (frame == 1) return PERIOD_M1;
   if (frame == 2) return PERIOD_M2;
   if (frame == 3) return PERIOD_M3;
   if (frame == 4) return PERIOD_M4;
   if (frame == 5) return PERIOD_M5;
   if (frame == 6) return PERIOD_M6;
   if (frame == 10) return PERIOD_M10;
   if (frame == 12) return PERIOD_M12;
   if (frame == 15) return PERIOD_M15;
   if (frame == 20) return PERIOD_M20;
   if (frame == 30) return PERIOD_M30;
   if (frame == 16385) return PERIOD_H1;
   if (frame == 16386) return PERIOD_H2;
   if (frame == 16387) return PERIOD_H3;
   if (frame == 16388) return PERIOD_H4;
   if (frame == 16390) return PERIOD_H6;
   if (frame == 16392) return PERIOD_H8;
   if (frame == 16396) return PERIOD_H12;
   if (frame == 16408) return PERIOD_D1;
   if (frame == 32769) return PERIOD_W1;
   return -1;
}

ENUM_ORDER_TYPE_FILLING GetFilling( const string Symb, const uint Type = ORDER_FILLING_FOK )    
{

  const ENUM_SYMBOL_TRADE_EXECUTION ExeMode = (ENUM_SYMBOL_TRADE_EXECUTION)::SymbolInfoInteger(Symb, SYMBOL_TRADE_EXEMODE);
  const int FillingMode = (int)::SymbolInfoInteger(Symb, SYMBOL_FILLING_MODE);

  return((FillingMode == 0 || (Type >= ORDER_FILLING_RETURN) || ((FillingMode & (Type + 1)) != Type + 1)) ?
         (((ExeMode == SYMBOL_TRADE_EXECUTION_EXCHANGE) || (ExeMode == SYMBOL_TRADE_EXECUTION_INSTANT)) ?
           ORDER_FILLING_RETURN : ((FillingMode == SYMBOL_FILLING_IOC) ? ORDER_FILLING_IOC : ORDER_FILLING_FOK)) :
          (ENUM_ORDER_TYPE_FILLING)Type);

}

string orderReturnCode(int code)
{
   if (code == 10008) return "Order place.";
   if (code == 10009) return "Request completed.";
   if (code == 10010) return "Partly request.";
   if (code == 10014) return "Invalid volume.";
   if (code == 10015) return "Invalid price.";
   if (code == 10016) return "Invalid stops";
   if (code == 10018) return "Market closed";
   if (code == 10019) return "No money.";
   if (code == 10031) return "No connection with server.";
   if (code == 10033) return "To many pendings";
   if (code == 10040) return "To many positions";

   return "Unknown error";
}

//+------------------------------------------------------------------+
double StrToNumber(string str)  {
//+------------------------------------------------------------------+
// Usage: strips all non-numeric characters out of a string, to return a numeric (double) value
//  valid numeric characters are digits 0,1,2,3,4,5,6,7,8,9, decimal point (.) and minus sign (-)
// Example: StrToNumber("the balance is $-34,567.98") returns the numeric value -34567.98
  int    dp   = -1;
  int    sgn  = 1;
  double num  = 0.0;
  for (int i=0; i<StringLen(str); i++)  
  {
    string s = StringSubstr(str,i,1);
    if (s == "-")  sgn = -sgn;   else
    if (s == ".")  dp = 0;       else
    if (s >= "0" && s <= "9")  {
      if (dp >= 0)  dp++;
      if (dp > 0)
        num = num + StringToInteger(s) / MathPow(10,dp);
      else
        num = num * 10 + StringToInteger(s);
    }
  }
  return(num*sgn);
}

MT5_F000 mt5_f000 = MT5_F000();
MT5_F001 mt5_f001 = MT5_F001();
MT5_F002 mt5_f002 = MT5_F002();
MT5_F003 mt5_f003 = MT5_F003();
MT5_F004 mt5_f004 = MT5_F004();
MT5_F005 mt5_f005 = MT5_F005();
MT5_F007 mt5_f007 = MT5_F007();

// ticket classes
MT5_F020 mt5_f020 = MT5_F020();
MT5_F021 mt5_f021 = MT5_F021();

// bar classes
MT5_F041 mt5_f041 = MT5_F041();
MT5_F042 mt5_f042 = MT5_F042();
MT5_F045 mt5_f045 = MT5_F045();

// orders and positions info retrieval
MT5_F060 mt5_f060 = MT5_F060();
MT5_F061 mt5_f061 = MT5_F061();
MT5_F062 mt5_f062 = MT5_F062();

// open/ close orders-positions
MT5_F070 mt5_f070 = MT5_F070();
MT5_F071 mt5_f071 = MT5_F071();
MT5_F072 mt5_f072 = MT5_F072();
MT5_F073 mt5_f073 = MT5_F073();

MT5_F075 mt5_f075 = MT5_F075();
MT5_F076 mt5_f076 = MT5_F076();


// --------------------------------------------------------------------
// EA user inputs
// --------------------------------------------------------------------
input ushort   ServerPort        = 1110;               // Prefer server port < 10000
input string   location         = "Market\\Pytrader MT5";         // folder and name indicator

// --------------------------------------------------------------------
// Global variables and constants
// --------------------------------------------------------------------

// Frequency for EventSetMillisecondTimer(). Doesn't need to 
// be very frequent, because it is just a back-up for the 
// event-driven handling in OnChartEvent()
#define TIMER_FREQUENCY_MS    500

// Server socket
ServerSocket * glbServerSocket = NULL;

// Array of current clients
ClientSocket * glbClients[];

// Watch for need to create timer;
bool glbCreatedTimer = false;


int secondsCounter = 60;
int maxSecondsCounter;




string comment;
bool newBar;
bool initializationActive = true;

int _handle = 0;
int _port;
double inputBuffer[2];

bool bDemo = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // If the EA is being reloaded, e.g. because of change of timeframe,
   // then we may already have done all the setup. See the 
   // termination code in OnDeinit.
   
   bool _DLL = (bool)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED);
   if (_DLL == false) {
      Alert("Allow DLL import. ");
      return(INIT_FAILED);     
   }
   
   string authorIndi = location;
   //Alert(authorIndi);
   
   // read the settings from the indicator
   _handle=iCustom(NULL, 0, authorIndi, ServerPort);
   //Alert(_handle);
   int quantity = CopyBuffer(_handle, 0, 0, 2, inputBuffer);
   if (quantity == 2)  {
      _port = inputBuffer[0];
      Print("Port: " + _port);
      quantity = CopyBuffer(_handle, 4, 0, 2, inputBuffer);
      if (inputBuffer[0] != 999) {     
            bDemo = true;
            _port = ServerPort;
            Alert("EA working in demo.");
      }
      else {bDemo = false;}
   }
   else 
   {
      Alert("EA working in demo.");
      bDemo = true;
      _port = ServerPort;
   }

   EventSetTimer(1);
   if (glbServerSocket) 
   {
      Print("Reloading EA with existing server socket");
   } 
   else 
   {
      // Create the server socket
      glbServerSocket = new ServerSocket(_port, false);
      if (glbServerSocket.Created()) 
      {
         Print("Server socket created");
   
         // Note: this can fail if MT4/5 starts up
         // with the EA already attached to a chart. Therefore,
         // we repeat in OnTick()
         glbCreatedTimer = EventSetMillisecondTimer(TIMER_FREQUENCY_MS);
      } 
      else 
      {
         Print("Server socket FAILED - is the port already in use?");
      }
   }
   
   comment = "";
   if (bDemo == false) {
      comment = comment + "\r\nPytrader MT5 server (licensed), port#: " + IntegerToString(ServerPort);
   }
   else {
      comment = comment + "\r\nPytrader MT5 server (demo), port#: " + IntegerToString(ServerPort);
   }
         
   Comment(comment);   

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
// --------------------------------------------------------------------
// Termination - free server socket and any clients
// --------------------------------------------------------------------

void OnDeinit(const int reason)
{
   Comment("");
   switch (reason) {
      case REASON_CHARTCHANGE:
         // Keep the server socket and all its clients if 
         // the EA is going to be reloaded because of a 
         // change to chart symbol or timeframe 
         break;
         
      default:
         // For any other unload of the EA, delete the 
         // server socket and all the clients 
         glbCreatedTimer = false;
         
         // Delete all clients currently connected
         for (int i = 0; i < ArraySize(glbClients); i++) {
            delete glbClients[i];
         }
         ArrayResize(glbClients, 0);
      
         // Free the server socket. *VERY* important, or else
         // the port number remains in use and un-reusable until
         // MT4/5 is shut down
         delete glbServerSocket;
         Print("Server socket terminated");
         break;
   }
}


// --------------------------------------------------------------------
// Use OnTick() to watch for failure to create the timer in OnInit()
// --------------------------------------------------------------------
void OnTick()
{
   if (!glbCreatedTimer) glbCreatedTimer = EventSetMillisecondTimer(TIMER_FREQUENCY_MS);
}

// --------------------------------------------------------------------
// Timer - accept new connections, and handle incoming data from clients.
// Secondary to the event-driven handling via OnChartEvent(). Most
// socket events should be picked up faster through OnChartEvent()
// rather than being first detected in OnTimer()
// --------------------------------------------------------------------
void OnTimer()
{

   initializationActive = false;
   // Accept any new pending connections
   //AcceptNewConnections();

   
   // Process any incoming data on each client socket,
   // bearing in mind that HandleSocketIncomingData()
   // can delete sockets and reduce the size of the array
   // if a socket has been closed

   for (int i = ArraySize(glbClients) - 1; i >= 0; i--) {
      HandleSocketIncomingData(i);
   }
}
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
//---
   
}
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
//---
   
}

// --------------------------------------------------------------------
// Event-driven functionality, turned on by #defining SOCKET_LIBRARY_USE_EVENTS
// before including the socket library. This generates dummy key-down
// messages when socket activity occurs, with lparam being the 
// .GetSocketHandle()
// --------------------------------------------------------------------

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if (id == CHARTEVENT_KEYDOWN) 
   {
      // If the lparam matches a .GetSocketHandle(), then it's a dummy
      // key press indicating that there's socket activity. Otherwise,
      // it's a real key press
         
      if (lparam == glbServerSocket.GetSocketHandle()) 
      {
         // Activity on server socket. Accept new connections
         Print("Chart event -- New server socket event - incoming connection");
         AcceptNewConnections();

      } else 
      {
         // Compare lparam to each client socket handle
         for (int i = 0; i < ArraySize(glbClients); i++) 
         {
            if (lparam == glbClients[i].GetSocketHandle()) 
            {
               HandleSocketIncomingData(i);
               return; // Early exit
            }
         }
         
         // If we get here, then the key press does not seem
         // to match any socket, and appears to be a real
         // key press event...
      }
   }
}

// --------------------------------------------------------------------
// Accepts new connections on the server socket, creating new
// entries in the glbClients[] array
// --------------------------------------------------------------------

void AcceptNewConnections()
{
   // Keep accepting any pending connections until Accept() returns NULL
   ClientSocket * pNewClient = NULL;
   do {
      if(initializationActive == true) {return;}
      pNewClient = glbServerSocket.Accept();
      if (pNewClient != NULL) 
      {
         int sz = ArraySize(glbClients);
         ArrayResize(glbClients, sz + 1);
         glbClients[sz] = pNewClient;
         Print("New client connection");
         
         pNewClient.Send("Hello new client;");
      }
      
   } while (pNewClient != NULL);
}

// --------------------------------------------------------------------
// Handles any new incoming data on a client socket, identified
// by its index within the glbClients[] array. This function
// deletes the ClientSocket object, and restructures the array,
// if the socket has been closed by the client
// --------------------------------------------------------------------

void HandleSocketIncomingData(int idxClient)
{
   ClientSocket * pClient = glbClients[idxClient];

   // Keep reading CRLF-terminated lines of input from the client
   // until we run out of new data
   bool bForceClose = false; // Client has sent a "close" message
   string strCommand;
   do {
      strCommand = pClient.Receive("!");
      //Print(strCommand);
      
      if (StringLen(strCommand) > 0)
      {
         ;
      }
      if (strCommand == "Hello") 
      {
         //Print("Hello:" + strCommand);
         pClient.Send(Symbol() + "!");
      } 
      else if (StringFind(strCommand,"F") >= 0)
      {
         string strResult = executeCommand(strCommand);
         pClient.Send(strResult);
      } 
      else if (strCommand != "") {
         // Potentially handle other commands etc here.
         // For example purposes, we'll simply print messages to the Experts log
         Print("<- ", strCommand);
      }
   } while (strCommand != "");

   // If the socket has been closed, or the client has sent a close message,
   // release the socket and shuffle the glbClients[] array
   if (!pClient.IsSocketConnected() || bForceClose) {
      Print("Client has disconnected");

      // Client is dead. Destroy the object
      delete pClient;
      
      // And remove from the array
      int ctClients = ArraySize(glbClients);
      for (int i = idxClient + 1; i < ctClients; i++) {
         glbClients[i - 1] = glbClients[i];
      }
      ctClients--;
      ArrayResize(glbClients, ctClients);
   }
}

//+------------------------------------------------------------------+

string executeCommand(string command)
{
   string returnString = "Error";
   string commandSplit[];
   
   StringSplit(command, char('#'), commandSplit);

   if (commandSplit[0] == "F000")
   {
      returnString = mt5_f000.Execute(command);
   }
   else if (commandSplit[0] == "F001")
   {
      returnString = mt5_f001.Execute(command);
   }
   else if (commandSplit[0] == "F002")
   {
      returnString = mt5_f002.Execute(command);
   }
   else if (commandSplit[0] == "F003")
   {
      returnString = mt5_f003.Execute(command);
   }
   else if (commandSplit[0] == "F004")
   {
      returnString = mt5_f004.Execute(command);
   }
   else if (commandSplit[0] == "F005")
   {
      returnString = mt5_f005.Execute(command);
   }
   else if (commandSplit[0] == "F007")
   {
      returnString = mt5_f007.Execute(command);
   }
   else if (commandSplit[0] == "F020")
   {
      returnString = mt5_f020.Execute(command);
   }
   else if (commandSplit[0] == "F021")
   {
      returnString = mt5_f021.Execute(command);
   }
   else if (commandSplit[0] == "F041")
   {
      returnString = mt5_f041.Execute(command);
   }
   else if (commandSplit[0] == "F042")
   {
      returnString = mt5_f042.Execute(command);
   }
   else if (commandSplit[0] == "F045")
   {
      returnString = mt5_f045.Execute(command);
   }
   else if (commandSplit[0] == "F060")
   {
      returnString = mt5_f060.Execute(command);
   }
   else if (commandSplit[0] == "F061")
   {
      returnString = mt5_f061.Execute(command);
   }
   else if (commandSplit[0] == "F062")
   {
      returnString = mt5_f062.Execute(command);
   }
   else if (commandSplit[0] == "F070")
   {
      returnString = mt5_f070.Execute(command);
   }
   else if (commandSplit[0] == "F071")
   {
      returnString = mt5_f071.Execute(command);
   }
   else if (commandSplit[0] == "F072")
   {
      returnString = mt5_f072.Execute(command);
   }
   else if (commandSplit[0] == "F073")
   {
      returnString = mt5_f073.Execute(command);
   }
   else if (commandSplit[0] == "F075")
   {
      returnString = mt5_f075.Execute(command);
   }
   else if (commandSplit[0] == "F076")
   {
      returnString = mt5_f076.Execute(command);
   }
   else
   {
      returnString = "F999:2:Command not implemented:xx:;";
   }

   return returnString;
}

//+------------------------------------------------------------------+
string stringReplaceOld(string str, string str1, string str2)  {
//+------------------------------------------------------------------+
// Usage: replaces every occurrence of str1 with str2 in str
// e.g. stringReplaceOld("ABCDE","CD","X") returns "ABXE"
  string outstr = "";
  for (int i=0; i<StringLen(str); i++)   {
    if (stringSubstrOld(str,i,StringLen(str1)) == str1)  {
      outstr = outstr + str2;
      i += StringLen(str1) - 1;
    }
    else
      outstr = outstr + stringSubstrOld(str,i,1);
  }
  return(outstr);
}

//+------------------------------------------------------------------+
string stringSubstrOld(string x,int a,int b=-1)  // THIS VERSION IS FOR >= B600
{
    bool debugSubstr = false; //TRUE; // Change to true to investigate whether this replacement function is ever truly needed, or if it makes no difference.
    if (debugSubstr)
    {
       int aa = a, bb = b;
       if (a < 0 ) aa = 0; 
       if (b <= 0 ) bb = -1;
       if (StringSubstr(x,a,b) != StringSubstr(x,aa,bb) ) 
       {
          // The 2nd arg change still makes a difference, as of build 670.
          if (a < 0) Print("2nd arg to StringSubstr WOULD have been <0 (",a,") which might corrupt strings in build>600. Changing to 0. Orig_args=(\"",x,"\",",a,",",b,")");
          if (b == 0 || b <= -2) Print("3rd arg to StringSubstr WOULD have been =",b,". Changing to -1 (=EOL). Orig_args=(\"",x,"\",",a,",",b,")");
          Print("WARNING: Use of stringSubstrOld(\"",x,"\",",a,",",b,")='",StringSubstr(x,a,b),"'"); // The output is so corrupted that it doesn't even output the final "'".  Hence, split this warning up into 2 lines. 
          Print("... which does not match b600 StringSubstr(\"",x,"\",",aa,",",bb,")='",StringSubstr(x,aa,bb),"' proving that Old behaves different. Consider fixing the original code to prevent using illegal values, to avoid these necessary adjustments to argument(s)");
          // NOTE: The *only* way to prove a problem with the modified arguments is to store this b600 result, and then compare with a b509 compiled program that runs the original(unmodified) command.  Does it get the same or different result?  
       }
    }
    if (a < 0) a = 0; // Stop odd behaviour.  If a<0, it might corrupt strings!!
    if (b<=0) b = -1; // new MQL4 EOL flag.   Formerly, a "0" was EOL. Is officially now -1.
    return(StringSubstr(x,a,b));
} 

//+------------------------------------------------------------------+
string stringReplace(string str, string str1, string str2)  {
//+------------------------------------------------------------------+
// Usage: replaces every occurrence of str1 with str2 in str
// e.g. StringReplace("ABCDE","CD","X") returns "ABXE"
  string outstr = "";
  for (int i=0; i<StringLen(str); i++)   {
    if (StringSubstr(str,i,StringLen(str1)) == str1)  {
      outstr = outstr + str2;
      i += StringLen(str1) - 1;
    }
    else
      outstr = outstr + StringSubstr(str,i,1);
  }
  return(outstr);
}

string filterComment(string _tofilter)
{
   string tmpString = "";
   
   tmpString = stringReplace(_tofilter, "#", "");
   tmpString = stringReplace(tmpString, "$", "");
   tmpString = stringReplace(tmpString, "!", "");
   
   return tmpString;
}

bool checkInstrumentsInDemo(string instrument)
{
   string demoInstruments[] = {"EURUSD", "AUDCHF", "NZDCHF", "GBPNZD", "USDCAD"};
   
   for (int u = 0; u < ArraySize(demoInstruments); u++) {
      if (StringFind(instrument, demoInstruments[u]) >= 0) {
         return true;
      }   
   }
   return false;
}