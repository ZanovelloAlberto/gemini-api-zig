const std = @import("std");

const GeminiOpts = struct {
    apikey: []const u8,
};
const Part = struct {
    text: []const u8,
};
const JSONReq = struct {
    contents: []const Content,
    const Content = struct {
        parts: []const Part,
    };
};
pub const JSONRes = struct {
    const Candidate = struct {
        const Content = struct {
            parts: []const Part,
            role: []const u8,
        };
        content: Content,
        finishReason: []const u8,
        avgLogprobs: f32,
    };
    const TokenDetail = struct {
        modality: []const u8,
        tokenCount: u32,
    };

    const UsageMetadata = struct {
        promptTokenCount: u32,
        candidatesTokenCount: u32,
        totalTokenCount: u32,
        promptTokensDetails: []const TokenDetail,
        candidatesTokensDetails: []const TokenDetail,
    };

    const ResponseData = struct {
        usageMetadata: UsageMetadata,
        modelVersion: []const u8,
    };

    usageMetadata: UsageMetadata,
    candidates: []Candidate,
};
pub fn Gemini(comptime opts: GeminiOpts) type {
    return struct {
        const Self = @This();
        const Models = .{
            "gemini-2.0-flash",
        };
        pub const QueryOut = struct {
            pub fn GetNext(self: *QueryOut) []const u8 {
                const ll = self.v.value.candidates[0].content.parts;
                const t = ll[self.partIndex].text;
                self.partIndex = (self.partIndex + 1) % ll.len;
                return t;
            }
            partIndex: usize = 0,
            v: std.json.Parsed(JSONRes),
            raw: []const u8,
            tis: *Self,
            fn free(ss: *@This()) void {
                ss.tis.alloc.free(ss.raw);
                ss.v.deinit();
            }
        };
        alloc: std.mem.Allocator,

        client: std.http.Client,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .client = std.http.Client{ .allocator = alloc },
                .alloc = alloc,
            };
        }

        pub fn query(self: *Self, text: []const u8) !QueryOut {
            const urlst = try std.fmt.allocPrint(
                self.alloc,
                "https://generativelanguage.googleapis.com/v1beta/models/{s}:generateContent?key=" ++ opts.apikey,
                .{
                    "gemini-2.0-flash",
                    // @import("key.zig").apiKey,
                },
            );
            defer self.alloc.free(urlst);
            // Parse the URI.
            const uri = try std.Uri.parse(urlst);

            const server_header_buffer: []u8 = try self.alloc.alloc(u8, 1024 * 8);

            defer self.alloc.free(server_header_buffer);
            const v: JSONReq = .{
                .contents = &[_]JSONReq.Content{
                    JSONReq.Content{
                        .parts = &[_]Part{
                            .{ .text = text },
                        },
                    },
                },
            };
            const strfied = try std.json.stringifyAlloc(self.alloc, v, .{});
            defer self.alloc.free(strfied);
            // Make the connection to the server.
            var req = try self.client.open(
                .POST,
                uri,
                .{
                    .server_header_buffer = server_header_buffer,
                    .headers = std.http.Client.Request.Headers{
                        .content_type = std.http.Client.Request.Headers.Value{
                            .override = "application/json",
                        },
                    },
                },
            );
            req.transfer_encoding = .{ .content_length = strfied.len };

            defer req.deinit();

            try req.send();
            var req_writer = req.writer();
            try req_writer.writeAll(strfied);
            try req.finish();
            try req.wait();

            // Print out the headers

            const body = try req.reader().readAllAlloc(self.alloc, 1024 * 8);
            const jv = try std.json.parseFromSlice(
                JSONRes,
                self.alloc,
                body,
                .{
                    .ignore_unknown_fields = true,
                },
            );
            return QueryOut{
                .raw = body,
                .tis = self,
                .v = jv,
            };

            // defer self.alloc.free(body);
        }

        pub fn deInit(self: *Self) void {
            self.client.deinit();
        }
    };
}

test "api" {
    // var g = Gemini(.{
    //     .apikey = @import("./key.zig").apiKey,
    // }).init(std.testing.allocator);

    // defer g.deInit();

    // var r = try g.query("ciao come va?");
    // std.debug.print("{s}", .{r.GetNext()});
    // std.debug.print("{s}", .{r.GetNext()});

    // var r2 = try g.query("dimmi la circonferenza del sole");
    // std.debug.print("{s}", .{r2.GetNext()});

    // defer r.free();
    // defer r2.free();
}
