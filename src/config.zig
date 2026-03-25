// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Config Module
//!
//! Re-exports the external config library for CLI use.
//!
//! Configuration management with:
//! - Multiple format support (TOML, JSON, YAML)
//! - XDG Base Directory compliance
//! - Precedence: flags > env > project > user > system > defaults
//! - Secret handling (file/stdin only, not flags/env)
//! - Validation hooks
//!
//! ## Usage
//!
//! ```zig
//! const config = @import("cli").config;
//!
//! // Parse any config file - format is auto-detected from extension
//! var value = try config.parseFile(allocator, "config.yaml");
//! defer value.deinit();
//!
//! // Access nested values with dot notation
//! const host = value.getString("server.host") orelse "localhost";
//! const port = value.getInt("server.port") orelse 8080;
//! ```

const ext_config = @import("config");

// Re-export external library types
pub const yaml = ext_config.yaml;
pub const toml = ext_config.toml;
pub const json = ext_config.json;

pub const loader = ext_config.loader;
pub const provenance = ext_config.provenance;
pub const xdg = ext_config.xdg;
pub const dotenv = ext_config.dotenv;
pub const secret = ext_config.secret;
pub const validate = ext_config.validate;

// Re-export commonly used types
pub const Loader = ext_config.Loader;
pub const LoadError = ext_config.LoadError;
pub const LoadOptions = ext_config.LoadOptions;
pub const Format = ext_config.Format;
pub const load = ext_config.load;

pub const Source = ext_config.Source;
pub const TrackedValue = ext_config.TrackedValue;
pub const ProvenanceTracker = ext_config.ProvenanceTracker;

pub const XdgPaths = ext_config.XdgPaths;
pub const getPaths = ext_config.getPaths;
pub const getConfigDir = ext_config.getConfigDir;
pub const getDataDir = ext_config.getDataDir;
pub const getCacheDir = ext_config.getCacheDir;

pub const SecretError = ext_config.SecretError;
pub const readFromFile = ext_config.readFromFile;
pub const readFromStdin = ext_config.readFromStdin;

pub const ValidationError = ext_config.ValidationError;

// Re-export unified value API
pub const Value = ext_config.Value;
pub const ValueType = ext_config.ValueType;
pub const MapEntry = ext_config.MapEntry;
pub const parseContent = ext_config.parseContent;
pub const parseFile = ext_config.parseFile;

// ============================================================================
// Tests
// ============================================================================

test "config re-exports: core symbols are accessible" {
    // Verify key symbols are importable (types, generic fns, and functions)
    _ = @TypeOf(Loader);
    _ = @TypeOf(LoadError);
    _ = @TypeOf(LoadOptions);
    _ = @TypeOf(Format);
    _ = @TypeOf(Value);
    _ = @TypeOf(ValueType);
    _ = @TypeOf(MapEntry);
    _ = @TypeOf(load);
    _ = @TypeOf(parseContent);
    _ = @TypeOf(parseFile);
}

test "config re-exports: provenance symbols are accessible" {
    _ = @TypeOf(Source);
    _ = @TypeOf(TrackedValue);
    _ = @TypeOf(ProvenanceTracker);
}

test "config re-exports: xdg and security symbols are accessible" {
    _ = @TypeOf(XdgPaths);
    _ = @TypeOf(getPaths);
    _ = @TypeOf(getConfigDir);
    _ = @TypeOf(getDataDir);
    _ = @TypeOf(getCacheDir);
    _ = @TypeOf(SecretError);
    _ = @TypeOf(readFromFile);
    _ = @TypeOf(readFromStdin);
    _ = @TypeOf(ValidationError);
}

test "config re-exports: sub-modules are accessible" {
    _ = @TypeOf(yaml);
    _ = @TypeOf(toml);
    _ = @TypeOf(json);
    _ = @TypeOf(loader);
    _ = @TypeOf(provenance);
    _ = @TypeOf(xdg);
    _ = @TypeOf(dotenv);
    _ = @TypeOf(secret);
    _ = @TypeOf(validate);
}
