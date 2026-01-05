
use bincode::{Encode, Decode};

#[derive(Encode, Decode, Debug, PartialEq)]
struct Person {
    name: String,
    age: u32,
    email: String,
}

fn main() {
    println!("=== Direct Bincode Usage Example ===\n");
    let person = Person {
        name: "Alice".to_string(),
        age: 30,
        email: "alice@example.com".to_string(),
    };

    println!("Original person: {:?}", person);
    let encoded = bincode::encode_to_vec(&person, bincode::config::standard())
        .expect("Failed to serialize");

    println!("Serialized length: {} bytes", encoded.len());
    println!("Serialized bytes: {:?}", encoded);
    let (decoded, _): (Person, _) = bincode::decode_from_slice(
        &encoded,
        bincode::config::standard(),
    )
    .expect("Failed to deserialize");

    println!("Deserialized person: {:?}", decoded);
    println!("Match: {}\n", person == decoded);
    let data = vec![1u8, 2, 3, 4, 5, 100, 200, 255];
    println!("Original bytes: {:?}", data);

    let encoded_bytes = bincode::encode_to_vec(&data, bincode::config::standard())
        .expect("Failed to serialize bytes");

    println!("Encoded length: {} bytes", encoded_bytes.len());

    let (decoded_bytes, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &encoded_bytes,
        bincode::config::standard(),
    )
    .expect("Failed to deserialize bytes");

    println!("Decoded bytes: {:?}", decoded_bytes);
    println!("Match: {}", data == decoded_bytes);
}

