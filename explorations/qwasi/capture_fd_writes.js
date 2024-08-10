const VERSION_ACCESSOR = '.qwasi.capture_fd_writes.version';
const STRUCT_ACCESSOR  = '.struct.captured_fd_writes{i32;u8[]}';

function drain_captured_fd_writes(exports) {
    const littleEndian = true;
    let _captured = exports[STRUCT_ACCESSOR];
    const ptr = _captured && _captured();
    var struct = new DataView(exports.memory.buffer, ptr);
    const i32len = struct.getInt32(0, littleEndian);
    const u8ptr = ptr + 4; // skip 4 bytes for i32len; remainder is u8[] data
    var buffer = Buffer.from(exports.memory.buffer, u8ptr, i32len);
    struct.setInt32(0, 0, littleEndian); // reset capture buffer used length to 0
    return {
	ptr: ptr,
	i32len: i32len,
	data: buffer.toString('utf-8'),
    };
}

module.exports = {
    VERSION_ACCESSOR, STRUCT_ACCESSOR, drain_captured_fd_writes
};

if (require.main) (async () => {
    async function test_captured_fd_writes(wasmfile) {
	var bytes = require('fs').readFileSync(wasmfile);
	var exports = (await WebAssembly.instantiate(bytes)).instance.exports;

	var results = {
	    version: exports[VERSION_ACCESSOR]?.call().toString(16),
	    result: exports['xmain']?.call(),
	    captured: drain_captured_fd_writes(exports),
	};
	return results;
    }

    var test = await test_captured_fd_writes(process.argv[2]);
    console.log(test);
    console.log('------------------------------------------------------');
    console.log(test.captured.data);
})();
