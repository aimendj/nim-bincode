use std::ptr;
use std::slice;

#[repr(C)]
pub enum BincodeError {
    Success = 0,
    NullPointer = 1,
    SerializationError = 2,
    DeserializationError = 3,
}

/// Create a bincode configuration that enforces:
/// - Little endian byte order
/// - Fixed integer encoding
/// - 64 KiB limit
fn bincode_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<65536>() // 64 KiB limit (65536 bytes)
}

/// # Safety
/// The `data` pointer must point to valid memory containing the data to serialize.
/// The returned pointer must be freed using `bincode_free_buffer`.
#[no_mangle]
pub unsafe extern "C" fn bincode_serialize(
    data: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    
    let vec = if len == 0 {
        Vec::<u8>::new()
    } else {
        if data.is_null() {
            return ptr::null_mut();
        }
        let slice = slice::from_raw_parts(data, len);
        slice.to_vec()
    };
    
    // Enforce 64 KiB limit before serialization
    if vec.len() > 65536 {
        *out_len = 0;
        return ptr::null_mut();
    }
    
    match bincode::encode_to_vec(&vec, bincode_config()) {
        Ok(encoded) => {
            // Also check encoded size doesn't exceed limit
            if encoded.len() > 65536 {
                *out_len = 0;
                return ptr::null_mut();
            }
            let mut result = encoded.into_boxed_slice();
            let ptr = result.as_mut_ptr();
            *out_len = result.len();
            let _ = Box::into_raw(result);
            ptr
        }
        Err(_) => {
            *out_len = 0;
            ptr::null_mut()
        }
    }
}

/// # Safety
/// The `data` pointer must point to valid bincode-encoded data.
/// The returned pointer must be freed using `bincode_free_buffer`.
#[no_mangle]
pub unsafe extern "C" fn bincode_deserialize(
    data: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    
    let slice = if len == 0 {
        &[]
    } else {
        if data.is_null() {
            return ptr::null_mut();
        }
        slice::from_raw_parts(data, len)
    };
    
    match bincode::decode_from_slice::<Vec<u8>, _>(
        slice,
        bincode_config(),
    ) {
        Ok((decoded, bytes_read)) => {
            // Reject trailing bytes: ensure all input bytes were consumed
            if bytes_read != slice.len() {
                *out_len = 0;
                return ptr::null_mut();
            }
            let mut result = decoded.into_boxed_slice();
            let ptr = result.as_mut_ptr();
            *out_len = result.len();
            let _ = Box::into_raw(result);
            ptr
        }
        Err(_) => {
            *out_len = 0;
            ptr::null_mut()
        }
    }
}

/// # Safety
/// The `ptr` must be a pointer returned by `bincode_serialize` or `bincode_deserialize`.
/// The `len` must be the length of the buffer.
#[no_mangle]
pub unsafe extern "C" fn bincode_free_buffer(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    
    let _ = Box::from_raw(slice::from_raw_parts_mut(ptr, len));
}

#[no_mangle]
pub extern "C" fn bincode_get_serialized_length(
    data: *const u8,
    len: usize,
) -> usize {
    if data.is_null() {
        return 0;
    }

    unsafe {
        let slice = slice::from_raw_parts(data, len);
        let vec: Vec<u8> = slice.to_vec();
        match bincode::encode_to_vec(&vec, bincode_config()) {
            Ok(encoded) => encoded.len(),
            Err(_) => 0,
        }
    }
}

