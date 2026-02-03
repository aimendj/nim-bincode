use bincode;

/// Create bincode config matching our FFI wrapper implementation
fn bincode_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<65536>()
}

// ============================================================================
// Category 1: Vec<u8> Format Tests
// ============================================================================

#[test]
fn test_empty_vec_u8_format() {
    let config = bincode_config();
    let empty: Vec<u8> = vec![];
    let encoded = bincode::encode_to_vec(&empty, config).unwrap();
    
    // Empty vec should be 8 zero bytes (u64 length = 0)
    assert_eq!(encoded.len(), 8);
    assert_eq!(encoded, [0, 0, 0, 0, 0, 0, 0, 0]);
}

#[test]
fn test_small_vec_u8_format() {
    let config = bincode_config();
    let small = vec![1u8, 2, 3, 4, 5];
    let encoded = bincode::encode_to_vec(&small, config).unwrap();
    
    // Should be 8 bytes (u64 length = 5) + 5 data bytes = 13 bytes total
    assert_eq!(encoded.len(), 13);
    assert_eq!(&encoded[..8], &[5, 0, 0, 0, 0, 0, 0, 0]); // length prefix
    assert_eq!(&encoded[8..], &[1, 2, 3, 4, 5]); // data
}

#[test]
fn test_single_byte_vec_u8_format() {
    let config = bincode_config();
    let single = vec![42u8];
    let encoded = bincode::encode_to_vec(&single, config).unwrap();
    
    // Should be 8 bytes (u64 length = 1) + 1 data byte = 9 bytes total
    assert_eq!(encoded.len(), 9);
    assert_eq!(&encoded[..8], &[1, 0, 0, 0, 0, 0, 0, 0]); // length prefix
    assert_eq!(encoded[8], 42); // data
}

#[test]
fn test_large_vec_u8_format() {
    let config = bincode_config();
    let large: Vec<u8> = (0..256).map(|i| i as u8).collect();
    let encoded = bincode::encode_to_vec(&large, config).unwrap();
    
    // Should be 8 bytes (u64 length = 256) + 256 data bytes = 264 bytes total
    assert_eq!(encoded.len(), 264);
    
    // Verify length prefix (256 = 0x00000100 in little-endian)
    assert_eq!(&encoded[..8], &[0, 1, 0, 0, 0, 0, 0, 0]);
    
    // Verify data
    for i in 0..256 {
        assert_eq!(encoded[8 + i], i as u8);
    }
}

#[test]
fn test_wrapper_vec_u8_format() {
    let config = bincode_config();
    let data = vec![1u8, 2, 3, 4, 5];
    let encoded = bincode::encode_to_vec(&data, config).unwrap();
    
    // Verify format matches wrapper: 8-byte u64 length prefix + data
    assert_eq!(encoded.len(), 13);
    assert_eq!(&encoded[..8], &[5, 0, 0, 0, 0, 0, 0, 0]); // length prefix (u64 = 5)
    assert_eq!(&encoded[8..], &[1, 2, 3, 4, 5]); // data
}

// ============================================================================
// Category 2: String Format Tests
// ============================================================================

#[test]
fn test_string_format() {
    let config = bincode_config();
    let hello = "Hello".to_string();
    let encoded = bincode::encode_to_vec(&hello, config).unwrap();
    
    // Should be 8 bytes (u64 length = 5) + 5 UTF-8 bytes = 13 bytes total
    assert_eq!(encoded.len(), 13);
    assert_eq!(&encoded[..8], &[5, 0, 0, 0, 0, 0, 0, 0]); // length prefix
    assert_eq!(&encoded[8..], b"Hello"); // UTF-8 bytes
}

#[test]
fn test_empty_string_format() {
    let config = bincode_config();
    let empty_str = "".to_string();
    let encoded = bincode::encode_to_vec(&empty_str, config).unwrap();
    
    // Empty string should be 8 zero bytes (u64 length = 0)
    assert_eq!(encoded.len(), 8);
    assert_eq!(encoded, [0, 0, 0, 0, 0, 0, 0, 0]);
}

#[test]
fn test_wrapper_string_format() {
    let config = bincode_config();
    let text = "Hello, bincode!                                                                                                                                       !";
    let text_bytes = text.as_bytes().to_vec();
    let encoded = bincode::encode_to_vec(&text_bytes, config).unwrap();
    
    // Verify format matches wrapper: 8-byte u64 length prefix + UTF-8 bytes
    assert_eq!(encoded.len(), 159); // 8 bytes length + 151 bytes data
    assert_eq!(&encoded[..8], &[151, 0, 0, 0, 0, 0, 0, 0]); // length prefix (u64 = 151)
    
    // Verify length decoding
    let length = u64::from_le_bytes([
        encoded[0], encoded[1], encoded[2], encoded[3],
        encoded[4], encoded[5], encoded[6], encoded[7],
    ]);
    assert_eq!(length, 151);
    assert_eq!(text_bytes.len(), 151);
}

// ============================================================================
// Category 3: Integer Format Tests
// ============================================================================

#[test]
fn test_u32_format() {
    let config = bincode_config();
    let u32_val: u32 = 42;
    let encoded = bincode::encode_to_vec(&u32_val, config).unwrap();
    
    // u32 should be 4 bytes, little-endian
    assert_eq!(encoded.len(), 4);
    assert_eq!(encoded, [0x2A, 0x00, 0x00, 0x00]);
}

#[test]
fn test_u32_encoding() {
    let config = bincode_config();
    
    let u32_test: u32 = 0x12345678;
    let encoded = bincode::encode_to_vec(&u32_test, config).unwrap();
    assert_eq!(encoded, [0x78, 0x56, 0x34, 0x12], "u32 encoding mismatch");
}

#[test]
fn test_u64_format() {
    let config = bincode_config();
    let u64_val: u64 = 0x1234567890ABCDEF;
    let encoded = bincode::encode_to_vec(&u64_val, config).unwrap();
    
    // u64 should be 8 bytes, little-endian
    assert_eq!(encoded.len(), 8);
    assert_eq!(encoded, [0xEF, 0xCD, 0xAB, 0x90, 0x78, 0x56, 0x34, 0x12]);
}

#[test]
fn test_u64_encoding() {
    let config = bincode_config();
    
    let u64_test: u64 = 0x0123456789ABCDEF;
    let encoded = bincode::encode_to_vec(&u64_test, config).unwrap();
    assert_eq!(encoded, [0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01], "u64 encoding mismatch");
}

#[test]
fn test_i32_format() {
    let config = bincode_config();
    let i32_val: i32 = -42;
    let encoded = bincode::encode_to_vec(&i32_val, config).unwrap();
    
    // i32 should be 4 bytes, little-endian, two's complement
    assert_eq!(encoded.len(), 4);
    assert_eq!(encoded, [0xD6, 0xFF, 0xFF, 0xFF]);
}

#[test]
fn test_i32_encoding() {
    let config = bincode_config();
    
    // i32: -1 (should be 0xFFFFFFFF)
    let i32_test: i32 = -1;
    let encoded = bincode::encode_to_vec(&i32_test, config).unwrap();
    assert_eq!(encoded, [0xFF, 0xFF, 0xFF, 0xFF], "i32 -1 encoding mismatch");
    
    // i32: 0x7FFFFFFF (max positive)
    let i32_max: i32 = 0x7FFFFFFF;
    let encoded_max = bincode::encode_to_vec(&i32_max, config).unwrap();
    assert_eq!(encoded_max, [0xFF, 0xFF, 0xFF, 0x7F], "i32 max encoding mismatch");
}

// ============================================================================
// Category 4: Length Encoding Verification Tests
// ============================================================================

#[test]
fn test_vec_u8_length_encoding() {
    let config = bincode_config();
    
    // Test various lengths
    for len in [0u64, 1, 5, 255, 256, 65535, 65536].iter() {
        let data: Vec<u8> = vec![0u8; *len as usize];
        let encoded = bincode::encode_to_vec(&data, config).unwrap();
        
        // Extract length bytes (first 8 bytes)
        let len_bytes = &encoded[..8];
        let decoded_len = u64::from_le_bytes([
            len_bytes[0], len_bytes[1], len_bytes[2], len_bytes[3],
            len_bytes[4], len_bytes[5], len_bytes[6], len_bytes[7],
        ]);
        
        assert_eq!(*len, decoded_len, "Length mismatch for length {}", len);
        assert_eq!(encoded.len(), 8 + *len as usize, "Total size mismatch for length {}", len);
    }
}

// ============================================================================
// Category 5: Standard vs Fixed Encoding Comparison Tests
// ============================================================================

#[test]
fn test_standard_vs_fixed_encoding_vec_u8() {
    let data = vec![1u8, 2, 3, 4, 5];
    
    // Standard config (variable-length encoding)
    let standard_config = bincode::config::standard();
    let encoded_standard = bincode::encode_to_vec(&data, standard_config).unwrap();
    
    // Fixed encoding config (matches our wrapper)
    let fixed_config = bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<65536>();
    let encoded_fixed = bincode::encode_to_vec(&data, fixed_config).unwrap();
    
    // Standard uses variable-length: first byte is length (5)
    assert_eq!(encoded_standard, [5, 1, 2, 3, 4, 5]);
    assert_eq!(encoded_standard.len(), 6);
    
    // Fixed uses 8-byte u64 length prefix
    assert_eq!(&encoded_fixed[..8], &[5, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(&encoded_fixed[8..], &[1, 2, 3, 4, 5]);
    assert_eq!(encoded_fixed.len(), 13);
}

#[test]
fn test_standard_vs_fixed_encoding_string() {
    let text = "Hello, bincode!                                                                                                                                       !";
    let text_bytes = text.as_bytes().to_vec();
    
    let standard_config = bincode::config::standard();
    let fixed_config = bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<65536>();
    
    let encoded_standard = bincode::encode_to_vec(&text_bytes, standard_config).unwrap();
    let encoded_fixed = bincode::encode_to_vec(&text_bytes, fixed_config).unwrap();
    
    // Standard: first byte is length (151 = 0x97)
    assert_eq!(encoded_standard[0], 151);
    assert_eq!(encoded_standard.len(), 152); // 1 byte length + 151 bytes data
    
    // Fixed: first 8 bytes are length (151 in little-endian u64)
    assert_eq!(&encoded_fixed[..8], &[151, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(encoded_fixed.len(), 159); // 8 bytes length + 151 bytes data
}

#[test]
fn test_standard_vs_fixed_encoding_empty() {
    let empty: Vec<u8> = vec![];
    
    let standard_config = bincode::config::standard();
    let fixed_config = bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<65536>();
    
    let encoded_standard = bincode::encode_to_vec(&empty, standard_config).unwrap();
    let encoded_fixed = bincode::encode_to_vec(&empty, fixed_config).unwrap();
    
    // Standard: single zero byte
    assert_eq!(encoded_standard, [0]);
    assert_eq!(encoded_standard.len(), 1);
    
    // Fixed: 8 zero bytes
    assert_eq!(encoded_fixed, [0, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(encoded_fixed.len(), 8);
}
