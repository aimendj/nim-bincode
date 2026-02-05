use std::fs;
use std::path::PathBuf;
use bincode;

// ============================================================================
// Constants
// ============================================================================

/// Test files for variable encoding deserialization
const DESERIALIZE_TEST_FILES_VARIABLE: &[&str] = &[
    "nim_var_001.bin",
    "nim_var_002.bin",
    "nim_var_003.bin",
    "nim_var_004.bin",
    "nim_var_005.bin",
    "nim_var_006.bin",
    "nim_var_007.bin",
    "nim_var_008.bin",
    "nim_var_009.bin",
    "nim_var_010.bin",
    "nim_var_011.bin",
    "nim_var_012.bin",
    "nim_var_013.bin",
    "nim_var_014.bin",
];

/// Test files for fixed 8-byte encoding deserialization
const DESERIALIZE_TEST_FILES_FIXED8: &[&str] = &[
    "nim_fixed8_001.bin",
    "nim_fixed8_002.bin",
    "nim_fixed8_003.bin",
    "nim_fixed8_004.bin",
    "nim_fixed8_005.bin",
    "nim_fixed8_006.bin",
    "nim_fixed8_007.bin",
    "nim_fixed8_008.bin",
    "nim_fixed8_009.bin",
    "nim_fixed8_010.bin",
    "nim_fixed8_011.bin",
    "nim_fixed8_012.bin",
    "nim_fixed8_013.bin",
    "nim_fixed8_014.bin",
];

// ============================================================================
// Configuration Functions
// ============================================================================

/// Variable-length encoding config (LEB128)
fn variable_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_variable_int_encoding()
        .with_limit::<4294967305>()
}

/// Fixed 8-byte encoding config
fn fixed8_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<4294967305>()
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Format a vector for logging - show full vector if <= 20 bytes, otherwise show size only
fn format_vec_for_log(data: &[u8]) -> String {
    if data.len() > 20 {
        format!("{} bytes", data.len())
    } else {
        format!("{:?}", data)
    }
}

/// Serialize data with variable-length encoding and write to file
fn serialize_to_file_variable(data: &[u8], filename: &str) -> Result<(), Box<dyn std::error::Error>> {
    let serialized = bincode::encode_to_vec(data, variable_config())?;
    let test_dir = PathBuf::from("target/test_data");
    fs::create_dir_all(&test_dir)?;
    let file_path = test_dir.join(filename);
    fs::write(&file_path, &serialized)?;
    Ok(())
}

/// Deserialize data that was serialized with variable-length encoding
fn deserialize_from_file_variable(filename: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let test_dir = PathBuf::from("target/test_data");
    let file_path = test_dir.join(filename);
    let serialized = fs::read(&file_path)?;
    let (deserialized, bytes_read): (Vec<u8>, _) = 
        bincode::decode_from_slice(&serialized, variable_config())?;
    
    if bytes_read != serialized.len() {
        return Err(format!("Trailing bytes detected: read {} of {} bytes", 
            bytes_read, serialized.len()).into());
    }
    
    Ok(deserialized)
}

/// Serialize data with fixed 8-byte encoding and write to file
fn serialize_to_file_fixed8(data: &[u8], filename: &str) -> Result<(), Box<dyn std::error::Error>> {
    let serialized = bincode::encode_to_vec(data, fixed8_config())?;
    let test_dir = PathBuf::from("target/test_data");
    fs::create_dir_all(&test_dir)?;
    let file_path = test_dir.join(filename);
    fs::write(&file_path, &serialized)?;
    Ok(())
}

/// Deserialize data that was serialized with fixed 8-byte encoding
fn deserialize_from_file_fixed8(filename: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let test_dir = PathBuf::from("target/test_data");
    let file_path = test_dir.join(filename);
    let serialized = fs::read(&file_path)?;
    let (deserialized, bytes_read): (Vec<u8>, _) = 
        bincode::decode_from_slice(&serialized, fixed8_config())?;
    
    if bytes_read != serialized.len() {
        return Err(format!("Trailing bytes detected: read {} of {} bytes", 
            bytes_read, serialized.len()).into());
    }
    
    Ok(deserialized)
}

// ============================================================================
// Test Case Data
// ============================================================================

/// Get test cases for serialization (data, filename pairs)
/// The prefix parameter determines the filename prefix (e.g., "rust_fixed", "rust_var", "rust_fixed8")
fn get_serialize_test_cases(prefix: &str) -> Vec<(Vec<u8>, String)> {
    vec![
        (vec![1u8, 2, 3, 4, 5], format!("{}_001.bin", prefix)),
        (vec![], format!("{}_002.bin", prefix)),
        (vec![0u8, 255, 128, 64], format!("{}_003.bin", prefix)),
        (vec![1u8; 100], format!("{}_004.bin", prefix)),
        ("Hello, World!".as_bytes().to_vec(), format!("{}_005.bin", prefix)),
        (vec![42u8], format!("{}_006.bin", prefix)),
        ("Test with émojis 🚀".as_bytes().to_vec(), format!("{}_007.bin", prefix)),
        (vec![0u8; 20 * 1024], format!("{}_008.bin", prefix)), // 20kB
        (vec![0u8; 250], format!("{}_009.bin", prefix)), // Just below 251 threshold (uses single byte)
        (vec![0u8; 251], format!("{}_010.bin", prefix)), // Just at 251 threshold (uses 0xfb + u16 LE)
        (vec![0u8; 65535], format!("{}_011.bin", prefix)), // Just below 2^16 threshold (uses 0xfb + u16 LE: 3 + 65535 = 65538)
        (vec![0u8; 65536], format!("{}_012.bin", prefix)), // Just at 2^16 threshold (uses 0xfc + u32 LE: 5 + 65536 = 65541)
        (vec![0u8; 4294967295], format!("{}_013.bin", prefix)), // Just below 2^32 threshold (uses 0xfc + u32 LE: 5 + 4294967295 = 4294967300)
        (vec![0u8; 4294967296], format!("{}_014.bin", prefix)), // Just at 2^32 threshold (uses 0xfd + u64 LE: 9 + 4294967296 = 4294967305)
    ]
}

/// Get expected data for deserialization tests
fn get_expected_data() -> Vec<Vec<u8>> {
    vec![
        vec![1u8, 2, 3, 4, 5],
        vec![],
        vec![0u8, 255, 128, 64],
        ("Hello, World!".as_bytes().to_vec()),
        vec![42u8],
        ("Test with émojis 🚀".as_bytes().to_vec()),
        vec![1u8; 100],
        vec![0u8; 20 * 1024], // 20kB
        vec![0u8; 250], // Just below 251 threshold (uses single byte)
        vec![0u8; 251], // Just at 251 threshold (uses 0xfb + u16 LE)
        vec![0u8; 65535], // Just below 2^16 threshold (uses 0xfb + u16 LE: 3 + 65535 = 65538)
        vec![0u8; 65536], // Just at 2^16 threshold (uses 0xfc + u32 LE: 5 + 65536 = 65541)
        vec![0u8; 4294967295], // Just below 2^32 threshold (uses 0xfc + u32 LE: 5 + 4294967295 = 4294967300)
        vec![0u8; 4294967296], // Just at 2^32 threshold (uses 0xfd + u64 LE: 9 + 4294967296 = 4294967305)
    ]
}
// ============================================================================
// Variable-Length Encoding (LEB128) Tests
// ============================================================================

#[test]
fn test_rust_serialize_nim_deserialize_variable() {
    let test_cases = get_serialize_test_cases("rust_var");

    for (original, filename) in test_cases {
        serialize_to_file_variable(&original, &filename)
            .expect(&format!("Failed to serialize {} to file", filename));
        println!("Serialized {} with variable encoding to {}", format_vec_for_log(&original), filename);
    }
}

#[test]
fn test_nim_serialize_rust_deserialize_variable() {
    let test_files = DESERIALIZE_TEST_FILES_VARIABLE;
    let expected_data = get_expected_data();

    for (filename, expected) in test_files.iter().zip(expected_data.iter()) {
        match deserialize_from_file_variable(filename) {
            Ok(deserialized) => {
                assert_eq!(&deserialized, expected, 
                    "Deserialized data from {} doesn't match expected", filename);
                println!("✓ Successfully deserialized {} with variable encoding: {}", filename, format_vec_for_log(&deserialized));
            }
            Err(e) => {
                panic!("Failed to deserialize {}: {}", filename, e);
            }
        }
    }
}

#[test]
fn test_byte_for_byte_compatibility_variable() {
    // Test that Rust variable-length encoding roundtrips correctly
    // Use a subset of expected data to avoid very large allocations
    let test_cases: Vec<Vec<u8>> = get_expected_data().into_iter().take(7).collect();

    for original in test_cases {
        let encoded = bincode::encode_to_vec(&original, variable_config())
            .expect("Rust variable-length serialization failed");

        let (decoded, bytes_read): (Vec<u8>, _) =
            bincode::decode_from_slice(&encoded, variable_config())
                .expect("Rust variable-length deserialization failed");

        assert_eq!(
            bytes_read,
            encoded.len(),
            "All bytes should be consumed for variable encoding"
        );
        assert_eq!(
            decoded, original,
            "Variable-length roundtrip should preserve data"
        );
    }
}

#[test]
fn test_marker_byte_prefixes_variable() {
    // Verify that variable-length encoding uses correct marker bytes (0xfb, 0xfc, 0xfd)
    let config = variable_config();
    
    // Test single byte encoding (< 251): length 250 should be single byte
    let data250 = vec![0u8; 250];
    let encoded250 = bincode::encode_to_vec(&data250, config)
        .expect("Rust variable-length serialization failed");
    assert_eq!(encoded250[0], 250u8, "Length 250 should use single byte encoding (no marker)");
    assert_eq!(encoded250.len(), 251, "Length 250: 1 byte length + 250 data");
    
    // Test 0xfb marker (251-65535): length 251 should use 0xfb + u16 LE
    let data251 = vec![0u8; 251];
    let encoded251 = bincode::encode_to_vec(&data251, config)
        .expect("Rust variable-length serialization failed");
    assert_eq!(encoded251[0], 0xfb, "Length 251 should use 0xfb marker");
    assert_eq!(encoded251.len(), 254, "Length 251: 3 bytes (0xfb + u16) + 251 data");
    
    // Test 0xfc marker (65536-4294967295): length 65536 should use 0xfc + u32 LE
    let data65536 = vec![0u8; 65536];
    let encoded65536 = bincode::encode_to_vec(&data65536, config)
        .expect("Rust variable-length serialization failed");
    assert_eq!(encoded65536[0], 0xfc, "Length 65536 should use 0xfc marker");
    assert_eq!(encoded65536.len(), 65541, "Length 65536: 5 bytes (0xfc + u32) + 65536 data");
    
    // Test 0xfd marker (4294967296+): length 4294967296 should use 0xfd + u64 LE
    // Note: This allocates 4GB, so it's slow but verifies the marker byte
    let data4gb = vec![0u8; 4294967296];
    let encoded4gb = bincode::encode_to_vec(&data4gb, config)
        .expect("Rust variable-length serialization failed");
    assert_eq!(encoded4gb[0], 0xfd, "Length 4294967296 should use 0xfd marker");
    assert_eq!(encoded4gb.len(), 4294967305, "Length 4294967296: 9 bytes (0xfd + u64) + 4294967296 data");
}

// ============================================================================
// Fixed 8-byte Encoding Tests
// ============================================================================

#[test]
fn test_rust_serialize_nim_deserialize_fixed8() {
    let test_cases = get_serialize_test_cases("rust_fixed8");

    for (original, filename) in test_cases {
        serialize_to_file_fixed8(&original, &filename)
            .expect(&format!("Failed to serialize {} to file", filename));
        println!("Serialized {} with fixed 8-byte encoding to {}", format_vec_for_log(&original), filename);
    }
}

#[test]
fn test_nim_serialize_rust_deserialize_fixed8() {
    let test_files = DESERIALIZE_TEST_FILES_FIXED8;
    let expected_data = get_expected_data();

    for (filename, expected) in test_files.iter().zip(expected_data.iter()) {
        match deserialize_from_file_fixed8(filename) {
            Ok(deserialized) => {
                assert_eq!(&deserialized, expected, 
                    "Deserialized data from {} doesn't match expected", filename);
                println!("✓ Successfully deserialized {} with fixed 8-byte encoding: {}", filename, format_vec_for_log(&deserialized));
            }
            Err(e) => {
                panic!("Failed to deserialize {}: {}", filename, e);
            }
        }
    }
}

#[test]
fn test_byte_for_byte_compatibility_fixed8() {
    // Test that Rust fixed 8-byte encoding roundtrips correctly
    // Use a subset of expected data to avoid very large allocations
    let test_cases: Vec<Vec<u8>> = get_expected_data().into_iter().take(7).collect();

    for original in test_cases {
        let encoded = bincode::encode_to_vec(&original, fixed8_config())
            .expect("Rust fixed8 serialization failed");

        let (decoded, bytes_read): (Vec<u8>, _) =
            bincode::decode_from_slice(&encoded, fixed8_config())
                .expect("Rust fixed8 deserialization failed");

        assert_eq!(
            bytes_read,
            encoded.len(),
            "All bytes should be consumed for fixed8 encoding"
        );
        assert_eq!(
            decoded, original,
            "Fixed8 roundtrip should preserve data"
        );
    }
}
