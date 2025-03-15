## how to get gemini api
https://aistudio.google.com/app/apikey



# install

`zig fetch --save git+https://github.com/ZanovelloAlberto/gemini-api-zig`


```zig
    const geminiz = b.dependency("geminiz", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("geminiz", geminiz.module("geminiz"));
```



# usage

```zig
const allocator = std.heap.page_allocator;

const GeminiAPI = GeminiClient(.{});
var client = GeminiAPI.init(allocator, api_key);
defer client.deinit();
var result = try client.generate(.gemini_2_0_flash, "Write a short story");
defer result.deinit();

while (result.getNext()) |text| {
    std.debug.print("Part: {s}\n", .{text});
}
```
