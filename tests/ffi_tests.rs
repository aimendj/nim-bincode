use std::ptr;
use std::slice;

use bincode::{Encode, Decode};
use bincode_wrapper::{
    bincode_serialize,
    bincode_deserialize,
    bincode_free_buffer,
    bincode_get_serialized_length,
};

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
        let native_result = bincode::encode_to_vec(&original, bincode::config::standard())
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
        let serialized = bincode::encode_to_vec(&original, bincode::config::standard())
            .expect("Serialization failed");
        
        let (native_result, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &serialized,
            bincode::config::standard(),
        ).expect("Native deserialization failed");
        
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
        
        let native_result = bincode::encode_to_vec(&original, bincode::config::standard())
            .expect("Native serialization failed");
        
        let ffi_result = serialize_via_ffi(&original)
            .expect("FFI serialization failed");

        assert_eq!(native_result, ffi_result, 
            "FFI serialization doesn't match native for string: {}", text);
        
        let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &native_result,
            bincode::config::standard(),
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
        let native_result = bincode::encode_to_vec(&original, bincode::config::standard())
            .expect("Native serialization failed");
        
        let ffi_result = serialize_via_ffi(&original)
            .expect("FFI serialization failed");

        assert_eq!(native_result, ffi_result);
        
        let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &native_result,
            bincode::config::standard(),
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

    let person_bytes = bincode::encode_to_vec(&person, bincode::config::standard())
        .expect("Failed to serialize Person");
    
    let native_result = bincode::encode_to_vec(&person_bytes, bincode::config::standard())
        .expect("Native serialization failed");
    
    let ffi_result = serialize_via_ffi(&person_bytes)
        .expect("FFI serialization failed");

    assert_eq!(native_result, ffi_result, "FFI serialization doesn't match native for Person struct");
    
    let (native_deserialized_bytes, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &native_result,
        bincode::config::standard(),
    ).expect("Native deserialization failed");
    
    let ffi_deserialized_bytes = deserialize_via_ffi(&ffi_result)
        .expect("FFI deserialization failed");

    assert_eq!(native_deserialized_bytes, ffi_deserialized_bytes);
    assert_eq!(person_bytes, ffi_deserialized_bytes);
    
    let (decoded_person, _): (Person, _) = bincode::decode_from_slice(
        &ffi_deserialized_bytes,
        bincode::config::standard(),
    ).expect("Failed to deserialize Person from FFI result");
    
    assert_eq!(person, decoded_person, "Person struct doesn't match after FFI roundtrip");

    let point = Point {
        x: 1.5,
        y: 2.7,
        z: 3.9,
    };

    let point_bytes = bincode::encode_to_vec(&point, bincode::config::standard())
        .expect("Failed to serialize Point");
    
    let native_result = bincode::encode_to_vec(&point_bytes, bincode::config::standard())
        .expect("Native serialization failed");
    
    let ffi_result = serialize_via_ffi(&point_bytes)
        .expect("FFI serialization failed");

    assert_eq!(native_result, ffi_result, "FFI serialization doesn't match native for Point struct");
    
    let ffi_deserialized_bytes = deserialize_via_ffi(&ffi_result)
        .expect("FFI deserialization failed");

    assert_eq!(point_bytes, ffi_deserialized_bytes);
    
    let (decoded_point, _): (Point, _) = bincode::decode_from_slice(
        &ffi_deserialized_bytes,
        bincode::config::standard(),
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
    
    let native_result = bincode::encode_to_vec(&mixed_data, bincode::config::standard())
        .expect("Native serialization failed");
    
    let ffi_result = serialize_via_ffi(&mixed_data)
        .expect("FFI serialization failed");

    assert_eq!(native_result, ffi_result);
    
    let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &native_result,
        bincode::config::standard(),
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
        let expected_len = bincode::encode_to_vec(&data, bincode::config::standard())
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
    
    let native_serialized = bincode::encode_to_vec(&empty_array, bincode::config::standard())
        .expect("Native serialization of empty array failed");
    
    let ffi_serialized = serialize_via_ffi(&empty_array)
        .expect("FFI serialization of empty array failed");
    
    assert_eq!(native_serialized, ffi_serialized, 
        "FFI serialization of empty array doesn't match native");
    
    let (native_deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &native_serialized,
        bincode::config::standard(),
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
        
        let expected_serialized = bincode::encode_to_vec(&empty_array, bincode::config::standard())
            .expect("Failed to encode empty array");
        assert_eq!(serialized_bytes, expected_serialized,
            "Serialized empty array should match expected bincode encoding");
        
        let (deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
            &serialized_bytes,
            bincode::config::standard(),
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
        
        let empty_encoded = bincode::encode_to_vec(&Vec::<u8>::new(), bincode::config::standard())
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
