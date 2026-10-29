// Spotify Connect devices on the local network for a build re-signed without Apple's multicast
// entitlement. Spotify finds the speakers, TVs and desktop apps on the Wi-Fi with an mDNS query of its
// own to 224.0.0.251:5353 (or [ff02::fb]:5353), and without the entitlement iOS refuses that send, so
// only the devices Spotify's cloud knows show. Bonjour needs no entitlement, only Info.plist's
// NSBonjourServices (plist/liquid-glass.plist, merged with Spotify's own by scripts/pipeline.sh) and the
// Local Network permission. So:
//
//   Connect.x            browses for _spotify-connect._tcp with Bonjour and resolves each receiver to
//                        its addresses, and rebinds Spotify's imports of sendto, sendmsg and recvfrom
//   SGConnectRelay.m     a Connect query whose multicast send failed is sent again by unicast to each
//                        receiver's mDNS port from a socket of the mod's own; each answer is passed on
//                        to Spotify's socket over loopback, and Spotify's recvfrom is told it came from
//                        the receiver, so Spotify's own discovery goes on unchanged
//   SGMDNS.m             the checks on the packets, bounds-checked against what the network sends
//
// No setting: with the entitlement the real send works and nothing is relayed, and with Local Network
// denied Bonjour finds nothing to send to. Checked on the Mac against harness/connect/.
#import <Foundation/Foundation.h>
#import <sys/socket.h>

// The mDNS port, and the longest datagram either check reads.
#define SGMDNSPort 5353
#define SGMDNSMaxLength 9000

// A standard query (QR clear, opcode 0) of 1 to 40 questions, at least one of them for a name under
// _spotify-connect._tcp.local (a subtype too).
BOOL SGMDNSIsConnectQuery(const uint8_t *packet, size_t length);

// An answer to the query of that transaction ID: QR set, opcode 0, not truncated, RCODE 0, 1 to 400
// records that all decode, and at least one class IN record owned by a Connect name, or a PTR to one.
BOOL SGMDNSIsConnectReply(const uint8_t *packet, size_t length, uint16_t queryID);

// The browser's addresses for one receiver, each a struct sockaddr_in or sockaddr_in6 with the mDNS
// port; nil or empty forgets the receiver.
void SGConnectSetReceiver(NSString *name, NSArray<NSData *> *addresses);
// Every receiver's addresses, from any thread.
NSArray<NSData *> *SGConnectReceiverAddresses(void);
// The address's IP as text, for the log.
NSString *SGConnectAddressText(const struct sockaddr *address);

// Starts a relay round for this query sent on `socket` (Spotify's), unless one for the same socket and
// bytes is running or four are. Returns NO when the socket is not one a round can answer: not UDP,
// connected, or with no local port.
BOOL SGConnectRelayQuery(int socket, const void *query, size_t length);

// The replacements Connect.x rebinds Spotify's imports to.
ssize_t SGConnectSendto(int socket, const void *buffer, size_t length, int flags, const struct sockaddr *to, socklen_t toLength);
ssize_t SGConnectSendmsg(int socket, const struct msghdr *message, int flags);
ssize_t SGConnectRecvfrom(int socket, void *buffer, size_t length, int flags, struct sockaddr *from, socklen_t *fromLength);
// Where they find the system's functions; Connect.x fills these through SGRebindImport, and while one
// is NULL the replacement calls the system's own.
extern ssize_t (*SGConnectRealSendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
extern ssize_t (*SGConnectRealSendmsg)(int, const struct msghdr *, int);
extern ssize_t (*SGConnectRealRecvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *);
