use std::ptr;
use std::slice;

use bincode::{Encode, Decode};
use bincode_wrapper::{
    bincode_serialize,
    bincode_deserialize,
    bincode_free_buffer,
    bincode_get_serialized_length,
};

/// Create the same bincode configuration used by the FFI functions
fn ffi_bincode_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<65536>()
}

// ============================================================================
// Helper Functions
// ============================================================================

fn serialize_via_ffi(data: &[u8]) -> Option<Vec<u8>> {
    unsafe {
        let mut out_len = 0;
        let ptr = bincode_serialize(data.as_ptr(), data.len(), &mut out_len);
        if ptr.is_null() {
            return None;
        }
        let result = if out_len == 0 {
            Vec::new()
        } else {
            slice::from_raw_parts(ptr, out_len).to_vec()
        };
        bincode_free_buffer(ptr, out_len);
        Some(result)
    }
}

fn deserialize_via_ffi(data: &[u8]) -> Option<Vec<u8>> {
    unsafe {
        let mut out_len = 0;
        let ptr = bincode_deserialize(data.as_ptr(), data.len(), &mut out_len);
        if ptr.is_null() {
            return None;
        }
        let result = if out_len == 0 {
            Vec::new()
        } else {
            slice::from_raw_parts(ptr, out_len).to_vec()
        };
        bincode_free_buffer(ptr, out_len);
        Some(result)
    }
}

// ============================================================================
// Basic Serialization/Deserialization Tests
// ============================================================================

#[test]
fn test_ffi_serialize_matches_native() {
    let test_cases: Vec<Vec<u8>> = vec![
        vec![1u8, 2, 3, 4, 5],
        vec![],
        vec![0u8, 255, 128, 64],
        vec![1u8; 1000],
        vec![255u8; 100],
        "Hello, World!".as_bytes().to_vec(),
        vec![0u8; 1],
        vec![42u8],
    ];

    for original in test_cases {
        let native_result = bincode::encode_to_vec(&original, ffi_bincode_config())
            .expect("Native serialization failed");
        
        let ffi_result = serialize_via_ffi(&original)
            .expect("FFI serialization failed");

        assert_eq!(native_result, ffi_result, 
            "FFI serialization doesn't match native for {:?}", original);
    }
}

#[test]
fn test_ffi_deserialize_matches_native() {
    let test_cases: Vec<Vec<u8>> = vec![
        vec![1u8, 2, 3, 4, 5],
        vec![0u8, 255, 128, 64],
        vec![1u8; 100],
        vec![],
        "Test string".as_bytes().to_vec(),
        vec![0u8; 50],
    ];

    for original in test_cases {
        let serialized = bincode::encode_to_vec(&original, ffi_bincode_config())
            .expect("Serialization failed");
        
        let (native_result, bytes_read): (Vec<u8>, _) = bincode::decode_from_slice(
            &serialized,
            ffi_bincode_config(),
        ).expect("Native deserialization failed");
        
        // Verify no trailing bytes (same check as FFI)
        assert_eq!(bytes_read, serialized.len(), "Native should consume all bytes");
        
        let ffi_result = deserialize_via_ffi(&serialized)
            .expect("FFI deserialization failed");

        assert_eq!(native_result, ffi_result,
            "FFI deserialization doesn't match native");
        assert_eq!(original, ffi_result,
            "FFI deserialization doesn't match original");
    }
}

#[test]
fn test_ffi_roundtrip() {
    let original = vec![1u8, 2, 3, 4, 5, 100, 200, 255];
    
    let serialized = serialize_via_ffi(&original)
        .expect("FFI serialization failed");
    
    let deserialized = deserialize_via_ffi(&serialized)
        .expect("FFI deserialization failed");

    assert_eq!(original, deserialized, "FFI roundtrip failed");
}

// ============================================================================
// Data Type Specific Tests
// ============================================================================

#[test]
fn test_ffi_with_strings() {
    let long_string = "Very long string: ".repeat(100);
    let test_strings: Vec<&str> = vec![
        "Hello, World!",
        "",
        "Test with émojis 🚀",
        &long_string,
        "Null\0byte",
    ];

    for text in test_strings {
        let original = text.as_bytes().to_vec();
        
        let native_result = bincode::encode_to_vec(&original, ffi_bincode_config())
            .expect("Native serialization failed");
        
        let ffi_result = serialize_via_ffi(&original)
            .expect("FFI serialization failed");

        assert_eq!(native_result, ffi_result, 
            "FFI serialization doesn't match native for string: {}", text);
        
        let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &native_result,
            ffi_bincode_config(),
        ).expect("Native deserialization failed");
        
        let ffi_deserialized = deserialize_via_ffi(&ffi_result)
            .expect("FFI deserialization failed");

        assert_eq!(native_deserialized, ffi_deserialized);
        assert_eq!(original, ffi_deserialized);
    }
}

#[test]
fn test_ffi_with_integers_as_bytes() {
    let test_cases: Vec<Vec<u8>> = vec![
        (0u32).to_le_bytes().to_vec(),
        (42u32).to_le_bytes().to_vec(),
        (u32::MAX).to_le_bytes().to_vec(),
        (0u64).to_le_bytes().to_vec(),
        (u64::MAX).to_le_bytes().to_vec(),
        (i32::MIN).to_le_bytes().to_vec(),
        (i32::MAX).to_le_bytes().to_vec(),
    ];

    for original in test_cases {
        let native_result = bincode::encode_to_vec(&original, ffi_bincode_config())
            .expect("Native serialization failed");
        
        let ffi_result = serialize_via_ffi(&original)
            .expect("FFI serialization failed");

        assert_eq!(native_result, ffi_result);
        
        let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &native_result,
            ffi_bincode_config(),
        ).expect("Native deserialization failed");
        
        let ffi_deserialized = deserialize_via_ffi(&ffi_result)
            .expect("FFI deserialization failed");

        assert_eq!(native_deserialized, ffi_deserialized);
        assert_eq!(original, ffi_deserialized);
    }
}

#[test]
fn test_ffi_with_structs() {
    #[derive(Encode, Decode, Debug, PartialEq)]
    struct Person {
        name: String,
        age: u32,
        email: String,
    }

    #[derive(Encode, Decode, Debug, PartialEq)]
    struct Point {
        x: f64,
        y: f64,
        z: f64,
    }

    let person = Person {
        name: "Alice".to_string(),
        age: 30,
        email: "alice@example.com".to_string(),
    };

    let person_bytes = bincode::encode_to_vec(&person, ffi_bincode_config())
        .expect("Failed to serialize Person");
    
    let native_result = bincode::encode_to_vec(&person_bytes, ffi_bincode_config())
        .expect("Native serialization failed");
    
    let ffi_result = serialize_via_ffi(&person_bytes)
        .expect("FFI serialization failed");

    assert_eq!(native_result, ffi_result, "FFI serialization doesn't match native for Person struct");
    
    let (native_deserialized_bytes, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &native_result,
        ffi_bincode_config(),
    ).expect("Native deserialization failed");
    
    let ffi_deserialized_bytes = deserialize_via_ffi(&ffi_result)
        .expect("FFI deserialization failed");

    assert_eq!(native_deserialized_bytes, ffi_deserialized_bytes);
    assert_eq!(person_bytes, ffi_deserialized_bytes);
    
    let (decoded_person, _): (Person, _) = bincode::decode_from_slice(
        &ffi_deserialized_bytes,
        ffi_bincode_config(),
    ).expect("Failed to deserialize Person from FFI result");
    
    assert_eq!(person, decoded_person, "Person struct doesn't match after FFI roundtrip");

    let point = Point {
        x: 1.5,
        y: 2.7,
        z: 3.9,
    };

    let point_bytes = bincode::encode_to_vec(&point, ffi_bincode_config())
        .expect("Failed to serialize Point");
    
    let native_result = bincode::encode_to_vec(&point_bytes, ffi_bincode_config())
        .expect("Native serialization failed");
    
    let ffi_result = serialize_via_ffi(&point_bytes)
        .expect("FFI serialization failed");

    assert_eq!(native_result, ffi_result, "FFI serialization doesn't match native for Point struct");
    
    let ffi_deserialized_bytes = deserialize_via_ffi(&ffi_result)
        .expect("FFI deserialization failed");

    assert_eq!(point_bytes, ffi_deserialized_bytes);
    
    let (decoded_point, _): (Point, _) = bincode::decode_from_slice(
        &ffi_deserialized_bytes,
        ffi_bincode_config(),
    ).expect("Failed to deserialize Point from FFI result");
    
    assert_eq!(point, decoded_point, "Point struct doesn't match after FFI roundtrip");
}

#[test]
fn test_ffi_with_mixed_data() {
    let mut mixed_data = Vec::new();
    mixed_data.extend_from_slice("Header: ".as_bytes());
    mixed_data.extend_from_slice(&(42u32).to_le_bytes());
    mixed_data.extend_from_slice(" | ".as_bytes());
    mixed_data.extend_from_slice(&(100u64).to_le_bytes());
    mixed_data.extend_from_slice(" | Footer".as_bytes());
    
    let native_result = bincode::encode_to_vec(&mixed_data, ffi_bincode_config())
        .expect("Native serialization failed");
    
    let ffi_result = serialize_via_ffi(&mixed_data)
        .expect("FFI serialization failed");

    assert_eq!(native_result, ffi_result);
    
    let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &native_result,
        ffi_bincode_config(),
    ).expect("Native deserialization failed");
    
    let ffi_deserialized = deserialize_via_ffi(&ffi_result)
        .expect("FFI deserialization failed");

    assert_eq!(native_deserialized, ffi_deserialized);
    assert_eq!(mixed_data, ffi_deserialized);
}

// ============================================================================
// Utility Function Tests
// ============================================================================

#[test]
fn test_ffi_get_serialized_length() {
    let test_cases = vec![
        vec![1u8, 2, 3, 4, 5],
        vec![],
        vec![0u8, 255],
    ];

    for data in test_cases {
        let expected_len = bincode::encode_to_vec(&data, ffi_bincode_config())
            .expect("Serialization failed")
            .len();
        
        let ffi_len = bincode_get_serialized_length(data.as_ptr(), data.len());
        
        assert_eq!(expected_len, ffi_len,
            "FFI length doesn't match native for {:?}", data);
    }
}

// ============================================================================
// Edge Case Tests
// ============================================================================

#[test]
fn test_ffi_empty_array() {
    let empty_array: Vec<u8> = vec![];
    
    let native_serialized = bincode::encode_to_vec(&empty_array, ffi_bincode_config())
        .expect("Native serialization of empty array failed");
    
    let ffi_serialized = serialize_via_ffi(&empty_array)
        .expect("FFI serialization of empty array failed");
    
    assert_eq!(native_serialized, ffi_serialized, 
        "FFI serialization of empty array doesn't match native");
    
    let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &native_serialized,
        ffi_bincode_config(),
    ).expect("Native deserialization of empty array failed");
    
    let ffi_deserialized = deserialize_via_ffi(&ffi_serialized)
        .expect("FFI deserialization of empty array failed");
    
    assert_eq!(native_deserialized, ffi_deserialized,
        "FFI deserialization of empty array doesn't match native");
    assert_eq!(empty_array, ffi_deserialized,
        "FFI roundtrip of empty array failed");
    
    let roundtrip_result = deserialize_via_ffi(&serialize_via_ffi(&empty_array).unwrap())
        .expect("FFI roundtrip of empty array failed");
    assert_eq!(empty_array, roundtrip_result,
        "FFI roundtrip of empty array doesn't match original");
    
    unsafe {
        let mut out_len = 0;
        let result = bincode_serialize(ptr::null(), 0, &mut out_len);
        assert!(!result.is_null(), "Should serialize empty array with null pointer");
        let serialized_bytes = if out_len == 0 {
            Vec::new()
        } else {
            slice::from_raw_parts(result, out_len).to_vec()
        };
        bincode_free_buffer(result, out_len);
        
        let expected_serialized = bincode::encode_to_vec(&empty_array, ffi_bincode_config())
            .expect("Failed to encode empty array");
        assert_eq!(serialized_bytes, expected_serialized,
            "Serialized empty array should match expected bincode encoding");
        
        let (deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &serialized_bytes,
            ffi_bincode_config(),
        ).expect("Failed to deserialize empty array");
        assert_eq!(deserialized, empty_array,
            "Deserialized empty array should match original");
    }
}

#[test]
fn test_ffi_null_pointer_handling() {
    unsafe {
        let mut out_len = 0;
        let result = bincode_serialize(ptr::null(), 0, &mut out_len);
        assert!(!result.is_null(), "Should serialize empty array successfully");
        bincode_free_buffer(result, out_len);
        
        let empty_encoded = bincode::encode_to_vec(&Vec::<u8>::new(), ffi_bincode_config())
            .expect("Failed to encode empty vec");
        let result = bincode_deserialize(empty_encoded.as_ptr(), empty_encoded.len(), &mut out_len);
        assert!(!result.is_null(), "Should deserialize empty array successfully");
        bincode_free_buffer(result, out_len);
        
        let result = bincode_serialize(ptr::null(), 5, &mut out_len);
        assert!(result.is_null(), "Should return null for null pointer with non-zero length");
        
        let len = bincode_get_serialized_length(ptr::null(), 0);
        assert_eq!(len, 0, "Should return 0 for null input with length 0");
    }
}

// ============================================================================
// Configuration Enforcement Tests
// ============================================================================

#[test]
fn test_reject_trailing_bytes() {
    // Serialize some data
    let original = vec![1u8, 2, 3, 4, 5];
    let serialized = serialize_via_ffi(&original)
        .expect("Serialization failed");
    
    // Append trailing bytes
    let mut with_trailing = serialized.clone();
    with_trailing.push(0xFF);
    with_trailing.push(0xAA);
    
    // Deserialization should fail due to trailing bytes
    let result = deserialize_via_ffi(&with_trailing);
    assert!(result.is_none(), "Should reject data with trailing bytes");
    
    // Valid data without trailing bytes should work
    let valid_result = deserialize_via_ffi(&serialized);
    assert!(valid_result.is_some(), "Should accept valid data without trailing bytes");
    assert_eq!(valid_result.unwrap(), original);
}

#[test]
fn test_64kib_limit() {
    // Create data that exceeds 64 KiB limit (accounting for encoding overhead)
    // With fixed int encoding, a Vec<u8> needs 8 bytes for length prefix
    // So we test with data that would result in >64 KiB encoded
    let large_data = vec![0u8; 65537]; // 64 KiB + 1 byte input
    
    // Serialization should fail due to limit (input size check)
    let result = serialize_via_ffi(&large_data);
    assert!(result.is_none(), "Should reject data exceeding 64 KiB limit");
    
    // Test with data that's close to but under the limit
    // Account for encoding overhead (8 bytes for length with fixed encoding)
    let near_limit = vec![0u8; 65528]; // 64 KiB - 8 bytes (leaves room for length prefix)
    let result = serialize_via_ffi(&near_limit);
    assert!(result.is_some(), "Should accept data near 64 KiB limit");
    
    // Verify the encoded result doesn't exceed 64 KiB
    let encoded = result.unwrap();
    assert!(encoded.len() <= 65536, "Encoded data should not exceed 64 KiB");
}

#[test]
fn test_little_endian_enforcement() {
    // Verify that integers are encoded in little-endian format
    // We'll test this indirectly by ensuring our encoding matches
    // bincode's little-endian + fixed int encoding
    
    let test_data = vec![0x01u8, 0x02, 0x03, 0x04];
    
    // Our FFI should produce the same result as bincode with explicit little-endian + fixed int
    let ffi_result = serialize_via_ffi(&test_data)
        .expect("FFI serialization failed");
    
    let native_le_fixed = bincode::encode_to_vec(
        &test_data,
        ffi_bincode_config()
    ).expect("Native LE+fixed serialization failed");
    
    assert_eq!(ffi_result, native_le_fixed, "FFI should use little-endian + fixed int encoding");
}

#[test]
fn test_fixed_int_encoding() {
    // Verify that fixed integer encoding is used
    // Fixed encoding means integers always use the same number of bytes
    // regardless of value (unlike variable-length encoding)
    
    let small_int_bytes = vec![42u8];
    let large_int_bytes = vec![255u8];
    
    // With fixed encoding, both should serialize similarly
    // (they're both single bytes, so this is a simple test)
    let small_serialized = serialize_via_ffi(&small_int_bytes)
        .expect("Serialization failed");
    let large_serialized = serialize_via_ffi(&large_int_bytes)
        .expect("Serialization failed");
    
    // Both should deserialize correctly
    let small_deserialized = deserialize_via_ffi(&small_serialized)
        .expect("Deserialization failed");
    let large_deserialized = deserialize_via_ffi(&large_serialized)
        .expect("Deserialization failed");
    
    assert_eq!(small_deserialized, small_int_bytes);
    assert_eq!(large_deserialized, large_int_bytes);
}
