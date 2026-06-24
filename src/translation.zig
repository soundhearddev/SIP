const std = @import("std");
const header = @import("header");
const protocol = @import("protocol");
const synet = @import("synet");

pub const KEY_SIZE: usize = 32;
pub const NONCE_SIZE: usize = 12;
pub const TAG_SIZE: usize = 16;

pub const MAX_PACKET_SIZE: usize = 16 * 1024 * 1024; // 16 MiB

pub const TranslationError = error{
    PacketTooSmall,
    AuthFailed,
    PacketTooLarge,
    ConnectionClosed,
    IoError,
    SocketError,
};

pub fn buildOutboundPacket(
    io: std.Io,
    allocator: std.mem.Allocator,
    src: [16]u8,
    dst: [16]u8,
    conn_id: u64,
    command: protocol.Command,
    payload: []const u8,
    key: [KEY_SIZE]u8,
) ![]u8 {
    const raw_len = header.HEADER_SIZE + payload.len;
    const raw = try allocator.alloc(u8, raw_len);
    defer allocator.free(raw);

    _ = try header.buildPacket(
        raw,
        src,
        dst,
        conn_id,
        command,
        payload,
    );

    return try encryptPacket(io, allocator, raw, key);
}

pub const InboundPacket = struct {
    parsed: header.ParsedPacket,
    _buf: []u8,
};

pub fn readInboundPacket(
    sock: synet.Socket,
    allocator: std.mem.Allocator,
    key: [KEY_SIZE]u8,
) !InboundPacket {
    var outer_buf: [header.OUTER_HEADER_SIZE]u8 = undefined;
    synet.recvExact(sock, &outer_buf) catch return TranslationError.SocketError;

    const outer = try header.parseOuter(&outer_buf);

    const payload_len = std.mem.readInt(
        u32,
        &outer.length,
        .big,
    );

    if (payload_len == 0)
        return TranslationError.PacketTooSmall;

    if (payload_len > MAX_PACKET_SIZE)
        return TranslationError.PacketTooLarge;

    const remaining =
        header.INNER_HEADER_SIZE +
        NONCE_SIZE +
        payload_len +
        TAG_SIZE;

    const encrypted = try allocator.alloc(
        u8,
        header.OUTER_HEADER_SIZE + remaining,
    );
    defer allocator.free(encrypted);

    @memcpy(
        encrypted[0..header.OUTER_HEADER_SIZE],
        &outer_buf,
    );

    synet.recvExact(
        sock,
        encrypted[header.OUTER_HEADER_SIZE..],
    ) catch return TranslationError.SocketError;

    const decrypted =
        try decryptPacket(
            allocator,
            encrypted,
            key,
        );
    errdefer allocator.free(decrypted);

    const parsed =
        try header.parsePacket(decrypted);

    return InboundPacket{
        .parsed = parsed,
        ._buf = decrypted,
    };
}

pub fn freeInboundPacket(allocator: std.mem.Allocator, pkt: InboundPacket) void {
    allocator.free(pkt._buf);
}

pub fn encryptPacket(
    io: std.Io,
    allocator: std.mem.Allocator,
    raw_packet: []const u8,
    key: [KEY_SIZE]u8,
) ![]u8 {
    if (raw_packet.len < header.HEADER_SIZE) return TranslationError.PacketTooSmall;

    const hdr = raw_packet[0..header.OUTER_HEADER_SIZE];
    const payload = raw_packet[header.OUTER_HEADER_SIZE..];

    var nonce: [NONCE_SIZE]u8 = undefined;
    const rng: std.Random.IoSource = .{ .io = io };
    rng.interface().bytes(&nonce);

    const out_len = header.OUTER_HEADER_SIZE + NONCE_SIZE + payload.len + TAG_SIZE;
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    @memcpy(out[0..header.OUTER_HEADER_SIZE], hdr);
    @memcpy(out[header.OUTER_HEADER_SIZE..][0..NONCE_SIZE], &nonce);

    const ct_start = header.OUTER_HEADER_SIZE + NONCE_SIZE;
    const ct_buf = out[ct_start..][0 .. payload.len + TAG_SIZE];

    std.crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(
        ct_buf[0..payload.len],
        ct_buf[payload.len..][0..TAG_SIZE],
        payload,
        hdr,
        nonce,
        key,
    );

    return out;
}

pub fn decryptPacket(
    allocator: std.mem.Allocator,
    data: []const u8,
    key: [KEY_SIZE]u8,
) ![]u8 {
    const min_len = header.HEADER_SIZE + NONCE_SIZE + TAG_SIZE;
    if (data.len < min_len) return TranslationError.PacketTooSmall;

    const hdr = data[0..header.OUTER_HEADER_SIZE];
    const nonce = data[header.OUTER_HEADER_SIZE..][0..NONCE_SIZE].*;
    const ct_and_tag = data[header.OUTER_HEADER_SIZE + NONCE_SIZE ..];

    if (ct_and_tag.len < TAG_SIZE) return TranslationError.PacketTooSmall;

    const pt_len = ct_and_tag.len - TAG_SIZE;
    const ciphertext = ct_and_tag[0..pt_len];
    const tag = ct_and_tag[pt_len..][0..TAG_SIZE].*;

    const out = try allocator.alloc(u8, header.OUTER_HEADER_SIZE + pt_len);
    errdefer allocator.free(out);
    @memcpy(out[0..header.OUTER_HEADER_SIZE], hdr);

    std.crypto.aead.chacha_poly.ChaCha20Poly1305.decrypt(
        out[header.OUTER_HEADER_SIZE..],
        ciphertext,
        tag,
        hdr,
        nonce,
        key,
    ) catch return TranslationError.AuthFailed;

    return out;
}

const testing = std.testing;

test "encrypt -> decrypt Roundtrip" {
    const allocator = testing.allocator;
    const io = testing.io;

    const key: [KEY_SIZE]u8 = [_]u8{0x42} ** KEY_SIZE;
    const src = [_]u8{0x01} ** 16;
    const dst = [_]u8{0x02} ** 16;
    const payload = "Hallo Welt, das ist ein Test-Payload!";

    var raw_buf: [header.HEADER_SIZE + payload.len]u8 = undefined;
    _ = try header.buildPacket(&raw_buf, src, dst, 0xDEADBEEF, .Data, payload);

    const encrypted = try encryptPacket(io, allocator, &raw_buf, key);
    defer allocator.free(encrypted);

    const decrypted = try decryptPacket(allocator, encrypted, key);
    defer allocator.free(decrypted);

    try testing.expectEqualSlices(u8, &raw_buf, decrypted);
}

test "decrypt schlägt fehl bei manipuliertem Ciphertext" {
    const allocator = testing.allocator;
    const io = testing.io;

    const key: [KEY_SIZE]u8 = [_]u8{0x55} ** KEY_SIZE;
    const src = [_]u8{0xAA} ** 16;
    const dst = [_]u8{0xBB} ** 16;

    var raw_buf: [header.HEADER_SIZE + 32]u8 = undefined;
    _ = try header.buildPacket(&raw_buf, src, dst, 1, .Data, "manipulier mich nicht!!!");

    const encrypted = try encryptPacket(io, allocator, &raw_buf, key);
    defer allocator.free(encrypted);

    encrypted[header.HEADER_SIZE + NONCE_SIZE] ^= 0xFF;

    try testing.expectError(
        TranslationError.AuthFailed,
        decryptPacket(allocator, encrypted, key),
    );
}

test "decrypt schlägt fehl bei manipuliertem Header (Additional Data)" {
    const allocator = testing.allocator;
    const io = testing.io;

    const key: [KEY_SIZE]u8 = [_]u8{0x77} ** KEY_SIZE;
    const src = [_]u8{0x11} ** 16;
    const dst = [_]u8{0x22} ** 16;

    var raw_buf: [header.HEADER_SIZE + 16]u8 = undefined;
    _ = try header.buildPacket(&raw_buf, src, dst, 2, .Keepalive, "header auth test");

    const encrypted = try encryptPacket(io, allocator, &raw_buf, key);
    defer allocator.free(encrypted);

    encrypted[2] ^= 0x01;

    try testing.expectError(
        TranslationError.AuthFailed,
        decryptPacket(allocator, encrypted, key),
    );
}

test "decrypt lehnt zu kurze Pakete ab" {
    const allocator = testing.allocator;
    const key: [KEY_SIZE]u8 = [_]u8{0x11} ** KEY_SIZE;
    const too_short = [_]u8{0} ** 10;

    try testing.expectError(
        TranslationError.PacketTooSmall,
        decryptPacket(allocator, &too_short, key),
    );
}

test "buildOutboundPacket hat korrekten Längen-Präfix" {
    const allocator = testing.allocator;
    const io = testing.io;

    const key: [KEY_SIZE]u8 = [_]u8{0x33} ** KEY_SIZE;
    const src = [_]u8{0x01} ** 16;
    const dst = [_]u8{0x02} ** 16;

    const wire = try buildOutboundPacket(
        io,
        allocator,
        src,
        dst,
        42,
        .Data,
        "test payload",
        key,
    );
    defer allocator.free(wire);

    try testing.expect(wire.len > 0);
    try testing.expectEqual(wire[0], header.MAGIC);
}
