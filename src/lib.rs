use std::ptr;
use std::slice;

#[repr(C)]
pub enum BincodeError {
    Success = 0,
    NullPointer = 1,
    SerializationError = 2,
    DeserializationError = 3,
}

/// # Safety
/// This function is unsafe because it dereferences raw pointers.
/// The `data` pointer must point to valid memory containing the data to serialize.
/// The returned pointer must be freed using `bincode_free_buffer`.
#[no_mangle]
pub unsafe extern "C" fn bincode_serialize(
    data: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if data.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    let slice = slice::from_raw_parts(data, len);
    let vec: Vec<u8> = slice.to_vec();
    
    match bincode::encode_to_vec(&vec, bincode::config::standard()) {
        Ok(encoded) => {
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
/// This function is unsafe because it dereferences raw pointers.
/// The `data` pointer must point to valid bincode-encoded data.
/// The returned pointer must be freed using `bincode_free_buffer`.
#[no_mangle]
pub unsafe extern "C" fn bincode_deserialize(
    data: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if data.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }

    let slice = slice::from_raw_parts(data, len);
    
    match bincode::decode_from_slice::<Vec<u8>, _>(
        slice,
        bincode::config::standard(),
    ) {
        Ok((decoded, _)) => {
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
/// This function is unsafe because it frees memory.
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
        match bincode::encode_to_vec(&vec, bincode::config::standard()) {
            Ok(encoded) => encoded.len(),
            Err(_) => 0,
        }
    }
}

