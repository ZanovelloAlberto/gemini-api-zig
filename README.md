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


