import Foundation
import Testing
import SpritesCore

// The exec WebSocket framing is an external wire contract: stream IDs
// 0=stdin 1=stdout 2=stderr 3=exit 4=stdin-EOF prefix each binary frame in
// non-TTY mode; TTY mode is raw bytes.
struct ExecFrameTests {
    @Test func nonTTYFramesCarryStreamIDPrefixes() {
        #expect(ExecFrame.decode(Data([1, 104, 105]), tty: false) == .stdout(Data("hi".utf8)))
        #expect(ExecFrame.decode(Data([2, 111]), tty: false) == .stderr(Data("o".utf8)))
        #expect(ExecFrame.decode(Data([3, 7]), tty: false) == .exit(7))
        #expect(ExecFrame.decode(Data(), tty: false) == nil)
        #expect(ExecFrame.encodeStdin(Data("ls".utf8), tty: false) == Data([0, 108, 115]))
        #expect(ExecFrame.encodedStdinEOF == Data([4]))
    }

    @Test func ttyFramesAreRawBytes() {
        #expect(ExecFrame.decode(Data("raw".utf8), tty: true) == .stdout(Data("raw".utf8)))
        #expect(ExecFrame.encodeStdin(Data("q".utf8), tty: true) == Data("q".utf8))
    }
}
