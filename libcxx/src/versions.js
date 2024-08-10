function octccstr(u64, endianswap) {
    var bytes = Array.from(new Uint8Array(new BigUint64Array([BigInt(u64)]).buffer));
    if (endianswap) bytes.reverse();
    return Buffer.from(bytes).toString('binary').replace(/\x00/g, ' ');
}

function module_detect_versions(exports) {
    return Object.keys(exports).filter((x)=>exports[x].call && /^[.].*?[.]version$/.test(x)).reduce((out, x)=>{
	try { var raw = exports[x](); } catch(e) { console.error(x, e); }
	var version;
	if (raw >= 0x20240000 && raw < 0x20990000) version = raw.toString(16);
	else version = octccstr(raw, true);
	out[x.split('.').slice(1,-1).join('.')] = { sraw: '0x'+raw.toString(16), raw, version };
	return out;
    }, {});
}

function maybe_dump_captured_fd_writes(exports) {
    const STRUCT_ACCESSOR  = '.struct.captured_fd_writes{i32;u8[]}';
    var ptr = exports['.struct.captured_fd_writes{i32;u8[]}']?.call();
    if (!ptr) return false;
    var len = new DataView(exports.memory.buffer).getInt32(ptr, true);
    var buffer = Buffer.from(exports.memory.buffer, ptr + 4, len);
    console.log({ ptr, len });
    console.log("--------------------------------------------------------------------------------");
    console.log(buffer.toString('utf-8'));
    console.log("--------------------------------------------------------------------------------");
}

(async () => {
    var exports = (await WebAssembly.instantiate(require('fs').readFileSync(process.argv[2]))).instance.exports;
    console.table(module_detect_versions(exports));
    if (exports.xmain) exports.xmain();
    maybe_dump_captured_fd_writes(exports);
})()
