const std = @import("std");

/// Represents a single part of content (typically text)
pub const ContentSegment = struct {
    text: []const u8,
};

/// Request structure for Gemini API
const RequestPayload = struct {
    contents: []const Content,
    pub const Content = struct {
        parts: []const ContentSegment,
    };
};

/// Response structure from Gemini API
pub const ResponseData = struct {
    pub const Candidate = struct {
        pub const Content = struct {
            parts: []const ContentSegment,
            role: []const u8,
        };
        content: Content,
        finishReason: []const u8,
        avgLogprobs: f32 = 0.0, // Added default value
    };

    pub const TokenDetail = struct {
        modality: []const u8,
        tokenCount: u32,
    };

    pub const UsageMetadata = struct {
        promptTokenCount: u32,
        candidatesTokenCount: u32,
        totalTokenCount: u32,
        promptTokensDetails: []const TokenDetail,
        candidatesTokensDetails: []const TokenDetail,
    };

    usageMetadata: UsageMetadata,
    candidates: []Candidate,
};

/// Configuration options for the Gemini API client
pub const GeminiConfig = struct {
    /// Base URL for the API (useful for testing or custom endpoints)
    base_url: []const u8 = "https://generativelanguage.googleapis.com/v1beta",
};
/// Gemini API client generator
pub fn GeminiClient(comptime config: GeminiConfig) type {
    return struct {
        const Self = @This();

        /// Available Gemini models
        pub const Model = enum {
            gemini_1_5_flash,
            gemini_1_5_flash_8b,
            gemini_2_0_flash,
            gemini_2_0_flash_exp,
            gemini_2_0_flash_thinking_exp_1219,
            gemini_1_0_pro,
            gemini_1_5_pro,

            pub fn toString(self: Model) []const u8 {
                return switch (self) {
                    .gemini_1_5_flash => "gemini-1.5-flash",
                    .gemini_1_5_flash_8b => "gemini-1.5-flash-8b",
                    .gemini_2_0_flash => "gemini-2.0-flash",
                    .gemini_2_0_flash_exp => "gemini-2.0-flash-exp",
                    .gemini_2_0_flash_thinking_exp_1219 => "gemini-2.0-flash-thinking-exp-1219",
                    .gemini_1_0_pro => "gemini-1.0-pro",
                    .gemini_1_5_pro => "gemini-1.5-pro",
                };
            }
        };

        /// Error set for Gemini operations
        pub const ClientError = error{
            NetworkFailure,
            InvalidResponse,
            ParseError,
            ApiFailure,
            MemoryError,
        };

        /// Structure representing query results
        pub const GenerationResult = struct {
            partIndex: usize = 0,
            parsed_response: std.json.Parsed(ResponseData),
            raw_response: []const u8,
            client: *Self,

            /// Gets the next part of the response
            pub fn getNext(self: *GenerationResult) ?[]const u8 {
                if (self.parsed_response.value.candidates.len == 0) return null;
                const parts = self.parsed_response.value.candidates[0].content.parts;
                if (parts.len == 0) return null;
                const text = parts[self.partIndex].text;
                self.partIndex = (self.partIndex + 1) % parts.len;
                return text;
            }

            /// Gets the full response text concatenated
            pub fn getFullText(self: *const GenerationResult) ![]const u8 {
                if (self.parsed_response.value.candidates.len == 0) return "";
                const parts = self.parsed_response.value.candidates[0].content.parts;
                var total_size: usize = 0;
                for (parts) |part| {
                    total_size += part.text.len;
                }

                const buffer = try self.client.allocator.alloc(u8, total_size);
                var offset: usize = 0;
                for (parts) |part| {
                    @memcpy(buffer[offset .. offset + part.text.len], part.text);
                    offset += part.text.len;
                }
                return buffer;
            }

            /// Frees resources associated with this query result
            pub fn deinit(self: *GenerationResult) void {
                self.client.allocator.free(self.raw_response);
                self.parsed_response.deinit();
            }
        };

        allocator: std.mem.Allocator,
        client: std.http.Client,
        api_key: []const u8,

        /// Initializes a new Gemini client
        pub fn init(
            alloc: std.mem.Allocator,
            api_key: []const u8,
        ) Self {
            return Self{
                .api_key = api_key,
                .client = std.http.Client{ .allocator = alloc },
                .allocator = alloc,
            };
        }

        /// Deinitializes the client and frees resources
        pub fn deinit(self: *Self) void {
            self.client.deinit();
        }

        /// Makes a query to the Gemini API with specified model
        pub fn generate(self: *Self, model: Model, prompt: []const u8) !GenerationResult {
            const endpoint = try std.fmt.allocPrint(
                self.allocator,
                "{s}/models/{s}:generateContent?key={s}",
                .{ config.base_url, model.toString(), self.api_key },
            );
            defer self.allocator.free(endpoint);

            const uri = try std.Uri.parse(endpoint);
            const header_buffer = try self.allocator.alloc(u8, 8 * 1024);
            defer self.allocator.free(header_buffer);

            const payload = RequestPayload{
                .contents = &[_]RequestPayload.Content{
                    .{ .parts = &[_]ContentSegment{.{ .text = prompt }} },
                },
            };
            const request_body = try std.json.stringifyAlloc(self.allocator, payload, .{});
            defer self.allocator.free(request_body);

            var request = try self.client.open(
                .POST,
                uri,
                .{
                    .server_header_buffer = header_buffer,
                    .headers = .{
                        .content_type = .{ .override = "application/json" },
                    },
                },
            );
            defer request.deinit();

            request.transfer_encoding = .{ .content_length = request_body.len };

            try request.send();
            try request.writer().writeAll(request_body);
            try request.finish();
            try request.wait();

            if (request.response.status != .ok) {
                return switch (request.response.status) {
                    .bad_request => ClientError.InvalidResponse,
                    .unauthorized => ClientError.ApiFailure,
                    else => ClientError.NetworkFailure,
                };
            }

            const response_content = try request.reader().readAllAlloc(self.allocator, 8 * 1024 * 1024);
            const parsed_data = std.json.parseFromSlice(
                ResponseData,
                self.allocator,
                response_content,
                .{ .ignore_unknown_fields = true },
            ) catch {
                self.allocator.free(response_content);
                return ClientError.ParseError;
            };

            return GenerationResult{
                .raw_response = response_content,
                .client = self,
                .parsed_response = parsed_data,
            };
        }

        /// Gets available models (placeholder - Gemini API doesn't provide this endpoint yet)
        pub fn getModels(self: *Self) []const Model {
            _ = self; // Suppress unused parameter warning
            return std.enums.values(Model);
        }

        /// Performs a streaming query (placeholder - to be implemented when API supports it)
        pub fn streamQuery(self: *Self, model: Model, text: []const u8) !void {
            _ = self;
            _ = model;
            _ = text;
            return error.NotImplemented;
        }
    };
}
// Tests
test "GeminiClient basic generation" {
    const allocator = std.testing.allocator;
    const api_key = std.posix.getenv("GEMINI_API_KEY") orelse @import("./key.zig").apiKey;

    const GeminiAPI = GeminiClient(.{});
    var client = GeminiAPI.init(allocator, api_key);
    defer client.deinit();

    var result = try client.generate(.gemini_2_0_flash, "Hello, how are you?");
    defer result.deinit();

    const first_segment = result.getNext();
    try std.testing.expect(first_segment != null);
    try std.testing.expect(first_segment.?.len > 0);
}

test "GeminiClient complete text" {
    const allocator = std.testing.allocator;
    const api_key = std.posix.getenv("GEMINI_API_KEY") orelse @import("./key.zig").apiKey;

    const GeminiAPI = GeminiClient(.{});
    var client = GeminiAPI.init(allocator, api_key);
    defer client.deinit();

    var result = try client.generate(.gemini_2_0_flash, "Write a short story");
    defer result.deinit();

    const full_text = try result.getFullText();
    defer allocator.free(full_text);
    try std.testing.expect(full_text.len > 0);
}
