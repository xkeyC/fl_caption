use pyo3::prelude::*;

pub fn call_hello_world() -> PyResult<String> {
    Python::attach(|py| {
        let module_path = std::env::current_exe()
            .ok()
            .and_then(|exe_path| exe_path.parent().map(|p| p.to_path_buf()))
            .unwrap_or_else(|| std::path::PathBuf::from("."));

        let python_path = module_path.join("python");
        let python_path_str = python_path.to_string_lossy();

        let sys = py.import("sys")?;
        let path = sys.getattr("path")?;
        path.call_method1("insert", (0, python_path_str.as_ref()))?;

        let hello_module = py.import("hello")?;
        let result: String = hello_module.call_method0("hello_world")?.extract()?;

        Ok(result)
    })
}
