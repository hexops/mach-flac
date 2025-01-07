const std = @import("std");
const c = @cImport({
    @cInclude("FLAC/stream_decoder.h");
    @cInclude("FLAC/stream_encoder.h");
});

const Flac = @This();

channels: u8,
sample_rate: u24,
bits_per_sample: u8,
samples: []i32,

pub const DecodeError = error{
    OutOfMemory,
    InvalidData,
};

pub fn decodeStream(allocator: std.mem.Allocator, stream: std.io.StreamSource) (DecodeError || std.io.StreamSource.ReadError)!Flac {
    var data = Decoder{ .allocator = allocator, .stream = stream };
    const decoder = c.FLAC__stream_decoder_new() orelse return error.OutOfMemory;

    switch (c.FLAC__stream_decoder_init_stream(
        decoder,
        Decoder.readCallback,
        Decoder.seekCallback,
        Decoder.tellCallback,
        Decoder.lengthCallback,
        Decoder.eofCallback,
        Decoder.writeCallback,
        Decoder.metadataCallback,
        Decoder.errorCallback,
        &data,
    )) {
        c.FLAC__STREAM_DECODER_INIT_STATUS_OK => {},
        c.FLAC__STREAM_DECODER_INIT_STATUS_UNSUPPORTED_CONTAINER => unreachable,
        c.FLAC__STREAM_DECODER_INIT_STATUS_INVALID_CALLBACKS => unreachable,
        c.FLAC__STREAM_DECODER_INIT_STATUS_MEMORY_ALLOCATION_ERROR => return error.OutOfMemory,
        c.FLAC__STREAM_DECODER_INIT_STATUS_ERROR_OPENING_FILE => unreachable,
        c.FLAC__STREAM_DECODER_INIT_STATUS_ALREADY_INITIALIZED => unreachable,
        else => unreachable,
    }

    if (c.FLAC__stream_decoder_process_until_end_of_stream(decoder) == 0) {
        switch (data.status) {
            c.FLAC__STREAM_DECODER_ERROR_STATUS_LOST_SYNC => unreachable,
            c.FLAC__STREAM_DECODER_ERROR_STATUS_BAD_HEADER => return error.InvalidData,
            c.FLAC__STREAM_DECODER_ERROR_STATUS_FRAME_CRC_MISMATCH => return error.InvalidData,
            c.FLAC__STREAM_DECODER_ERROR_STATUS_UNPARSEABLE_STREAM => return error.InvalidData,
            c.FLAC__STREAM_DECODER_ERROR_STATUS_BAD_METADATA => return error.InvalidData,
            else => unreachable,
        }
    }

    return .{
        .channels = data.channels,
        .sample_rate = data.sample_rate,
        .bits_per_sample = data.bits_per_sample,
        .samples = data.samples,
    };
}

const Decoder = struct {
    allocator: std.mem.Allocator,
    stream: std.io.StreamSource,
    channels: u8 = 0,
    sample_rate: u24 = 0,
    bits_per_sample: u8 = 0,
    total_samples: usize = 0,
    status: c.FLAC__StreamDecoderErrorStatus = undefined,
    samples: []i32 = &.{},
    sample_index: usize = 0,

    fn readCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        buffer: [*c]c.FLAC__byte,
        bytes: [*c]usize,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamDecoderReadStatus {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));

        if (bytes.* > 0) {
            bytes.* = data.stream.read(buffer[0..bytes.*]) catch return c.FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM;
            return c.FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
        }

        return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT;
    }

    fn seekCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        absolute_byte_offset: u64,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamDecoderSeekStatus {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));
        data.stream.seekTo(absolute_byte_offset) catch return c.FLAC__STREAM_DECODER_SEEK_STATUS_ERROR;
        return c.FLAC__STREAM_DECODER_SEEK_STATUS_OK;
    }

    fn tellCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        absolute_byte_offset: [*c]u64,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamDecoderTellStatus {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));
        absolute_byte_offset.* = data.stream.getPos() catch return c.FLAC__STREAM_DECODER_TELL_STATUS_ERROR;
        return c.FLAC__STREAM_DECODER_TELL_STATUS_OK;
    }

    fn lengthCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        stream_length: [*c]u64,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamDecoderLengthStatus {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));
        stream_length.* = data.stream.getEndPos() catch return c.FLAC__STREAM_DECODER_LENGTH_STATUS_ERROR;
        return c.FLAC__STREAM_DECODER_LENGTH_STATUS_OK;
    }

    fn eofCallback(_: [*c]const c.FLAC__StreamDecoder, user_data: ?*anyopaque) callconv(.C) c_int {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));
        const pos = data.stream.getPos() catch return 1;
        const end_pos = data.stream.getEndPos() catch return 1;
        return @intFromBool(pos == end_pos);
    }

    fn writeCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        frame: [*c]const c.FLAC__Frame,
        buffer: [*c]const [*c]const c.FLAC__int32,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamDecoderWriteStatus {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));

        if (data.total_samples == 0) {
            if (frame.*.header.blocksize > data.samples.len - data.sample_index) {
                const size = data.samples.len + data.channels * frame.*.header.blocksize;
                data.samples = data.allocator.realloc(data.samples, size) catch {
                    return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
                };
            }
        } else {
            if (data.samples.len == 0) {
                const size = data.total_samples * data.channels;
                data.samples = data.allocator.alloc(i32, size) catch {
                    return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
                };
            }
        }

        if (frame.*.header.channels == 3) {
            for (0..frame.*.header.blocksize) |i| {
                const center = @divTrunc(buffer[2][i], 2);
                const left = (buffer[0][i]) + center;
                const right = (buffer[1][i]) + center;
                data.samples[data.sample_index] = left;
                data.samples[data.sample_index + 1] = right;
                data.sample_index += 2;
            }
        } else {
            for (0..frame.*.header.blocksize) |i| {
                for (0..data.channels) |ch| {
                    const sample = buffer[ch][i];
                    data.samples[data.sample_index] = sample;
                    data.sample_index += 1;
                }
            }
        }

        return c.FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
    }

    fn metadataCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        metadata: [*c]const c.FLAC__StreamMetadata,
        user_data: ?*anyopaque,
    ) callconv(.C) void {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));
        data.channels = switch (metadata.*.data.stream_info.channels) {
            3 => 2, // We'll drop the center channel and mix it with Left and Right channels
            else => @intCast(metadata.*.data.stream_info.channels),
        };
        data.sample_rate = @intCast(metadata.*.data.stream_info.sample_rate);
        data.bits_per_sample = @intCast(metadata.*.data.stream_info.bits_per_sample);
        data.total_samples = @intCast(metadata.*.data.stream_info.total_samples);
    }

    fn errorCallback(
        _: [*c]const c.FLAC__StreamDecoder,
        status: c.FLAC__StreamDecoderErrorStatus,
        user_data: ?*anyopaque,
    ) callconv(.C) void {
        const data = @as(*Decoder, @ptrCast(@alignCast(user_data)));
        data.status = status;
    }
};

pub const EncodeError = error{
    OutOfMemory,
    SeekingFailed,
    InvalidSampleRate,
};

/// TODO: encoder is buggy and doesn't work yet (UB?)
pub fn encodeStream(
    stream: std.io.StreamSource,
    channels: u8,
    bits_per_sample: u8,
    sample_rate: u24,
    samples: []const i32,
    compression_level: ?u8,
) (EncodeError || std.io.StreamSource.WriteError)!void {
    var data = Encoder{ .stream = stream };
    const encoder = c.FLAC__stream_encoder_new() orelse return error.OutOfMemory;
    defer _ = c.FLAC__stream_encoder_delete(encoder);

    _ = c.FLAC__stream_encoder_set_channels(encoder, channels);
    _ = c.FLAC__stream_encoder_set_bits_per_sample(encoder, bits_per_sample);
    _ = c.FLAC__stream_encoder_set_sample_rate(encoder, sample_rate);
    _ = c.FLAC__stream_encoder_set_total_samples_estimate(encoder, samples.len);
    if (compression_level) |level| {
        std.debug.assert(level <= 8);
        _ = c.FLAC__stream_encoder_set_compression_level(encoder, level);
    }

    switch (c.FLAC__stream_encoder_init_stream(
        encoder,
        Encoder.writeCallback,
        Encoder.seekCallback,
        Encoder.tellCallback,
        null,
        &data,
    )) {
        c.FLAC__STREAM_ENCODER_INIT_STATUS_OK => {},
        c.FLAC__STREAM_ENCODER_INIT_STATUS_ENCODER_ERROR => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_UNSUPPORTED_CONTAINER => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_CALLBACKS => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_NUMBER_OF_CHANNELS => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_BITS_PER_SAMPLE => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_SAMPLE_RATE => return error.InvalidSampleRate,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_BLOCK_SIZE => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_MAX_LPC_ORDER => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_BLOCK_SIZE_TOO_SMALL_FOR_LPC_ORDER => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_NOT_STREAMABLE => unreachable,
        c.FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_METADATA => unreachable,
        else => unreachable,
    }

    if (c.FLAC__stream_encoder_process_interleaved(encoder, samples.ptr, @intCast(samples.len)) == 0) {
        switch (c.FLAC__stream_encoder_get_state(encoder)) {
            c.FLAC__STREAM_ENCODER_OK => {},
            c.FLAC__STREAM_ENCODER_UNINITIALIZED => unreachable,
            c.FLAC__STREAM_ENCODER_OGG_ERROR => unreachable,
            c.FLAC__STREAM_ENCODER_VERIFY_DECODER_ERROR => unreachable,
            c.FLAC__STREAM_ENCODER_VERIFY_MISMATCH_IN_AUDIO_DATA => unreachable,
            c.FLAC__STREAM_ENCODER_CLIENT_ERROR => return error.SeekingFailed,
            c.FLAC__STREAM_ENCODER_IO_ERROR => unreachable,
            c.FLAC__STREAM_ENCODER_FRAMING_ERROR => unreachable,
            c.FLAC__STREAM_ENCODER_MEMORY_ALLOCATION_ERROR => return error.OutOfMemory,
            else => unreachable,
        }
    }

    _ = c.FLAC__stream_encoder_finish(encoder);
}

const Encoder = struct {
    stream: std.io.StreamSource,

    fn writeCallback(
        _: [*c]const c.FLAC__StreamEncoder,
        buffer: [*c]const c.FLAC__byte,
        bytes: usize,
        _: u32,
        _: u32,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamEncoderWriteStatus {
        const data = @as(*Encoder, @ptrCast(@alignCast(user_data)));
        _ = data.stream.write(buffer[0..bytes]) catch return c.FLAC__STREAM_ENCODER_WRITE_STATUS_FATAL_ERROR;
        return c.FLAC__STREAM_ENCODER_WRITE_STATUS_OK;
    }

    fn seekCallback(
        _: [*c]const c.FLAC__StreamEncoder,
        absolute_byte_offset: u64,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamEncoderSeekStatus {
        const data = @as(*Encoder, @ptrCast(@alignCast(user_data)));
        data.stream.seekTo(absolute_byte_offset) catch return c.FLAC__STREAM_ENCODER_SEEK_STATUS_ERROR;
        return c.FLAC__STREAM_ENCODER_SEEK_STATUS_OK;
    }

    fn tellCallback(
        _: [*c]const c.FLAC__StreamEncoder,
        absolute_byte_offset: [*c]u64,
        user_data: ?*anyopaque,
    ) callconv(.C) c.FLAC__StreamEncoderTellStatus {
        const data = @as(*Encoder, @ptrCast(@alignCast(user_data)));
        absolute_byte_offset.* = data.stream.getPos() catch return c.FLAC__STREAM_ENCODER_TELL_STATUS_ERROR;
        return c.FLAC__STREAM_ENCODER_TELL_STATUS_OK;
    }
};
