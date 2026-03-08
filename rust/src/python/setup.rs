use pyo3::prelude::*;

pub fn setup_python_path(py: Python<'_>) -> PyResult<()> {
    let sys = py.import("sys")?;
    let path = sys.getattr("path")?;

    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|exe_path| exe_path.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| std::path::PathBuf::from("."));

    let (python_env, python_module) = find_python_paths(&exe_dir);
    let python_lib = python_env.join("Lib").join("site-packages");

    log::info!("[setup_python_path] exe_dir: {:?}", exe_dir);
    log::info!("[setup_python_path] python_env: {:?}", python_env);
    log::info!("[setup_python_path] python_lib: {:?}", python_lib);
    log::info!("[setup_python_path] python_module: {:?}", python_module);

    let path_list: Vec<String> = path.extract()?;
    let mut new_paths = vec![
        python_module.to_string_lossy().to_string(),
        python_lib.to_string_lossy().to_string(),
    ];

    for p in path_list {
        if !new_paths.contains(&p) {
            new_paths.push(p);
        }
    }

    path.call_method1("clear", ())?;
    for p in new_paths {
        path.call_method1("append", (&p,))?;
    }

    Ok(())
}

fn find_python_paths(exe_dir: &std::path::Path) -> (std::path::PathBuf, std::path::PathBuf) {
    let python_env = exe_dir.join("python_env");
    let python_module = exe_dir.join("python");

    if python_env.exists() && python_module.exists() {
        return (python_env, python_module);
    }

    if let Some(project_root) = find_project_root(exe_dir) {
        let env_path = project_root
            .join("python_build_workspace")
            .join("python_env");
        let module_path = project_root.join("python");

        if env_path.exists() && module_path.exists() {
            return (env_path, module_path);
        }
    }

    (python_env, python_module)
}

fn find_project_root(start_dir: &std::path::Path) -> Option<std::path::PathBuf> {
    let mut current = start_dir.to_path_buf();

    for _ in 0..10 {
        if current.join("pubspec.yaml").exists() {
            return Some(current);
        }

        if !current.pop() {
            break;
        }
    }

    None
}
