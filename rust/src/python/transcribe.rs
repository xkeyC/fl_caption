use pyo3::prelude::*;

use super::setup::setup_python_path;

pub fn call_hello_world() -> PyResult<String> {
    Python::attach(|py| {
        setup_python_path(py)?;

        let hello_module = py.import("hello")?;
        let result: String = hello_module.call_method0("hello_world")?.extract()?;

        Ok(result)
    })
}
