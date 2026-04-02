local jit = modules._G.jit;
local ffi = modules._G.require("ffi");
local io = modules._G.require("io");

if (modules._G.cdef_cmd == nil) then
	modules._G.cdef_cmd = true;
ffi.cdef[[
    typedef void* HANDLE;
    typedef int BOOL;
    typedef unsigned long DWORD;
    typedef const char* LPCSTR;
    typedef char* LPSTR;
    typedef void* LPVOID;
    typedef unsigned long ULONG_PTR;

    typedef struct _SECURITY_ATTRIBUTES {
      DWORD  nLength;
      void*  lpSecurityDescriptor;
      BOOL   bInheritHandle;
    } SECURITY_ATTRIBUTES, *PSECURITY_ATTRIBUTES, *LPSECURITY_ATTRIBUTES;

    typedef struct _STARTUPINFOA {
      DWORD  cb;
      LPSTR  lpReserved;
      LPSTR  lpDesktop;
      LPSTR  lpTitle;
      DWORD  dwX;
      DWORD  dwY;
      DWORD  dwXSize;
      DWORD  dwYSize;
      DWORD  dwXCountChars;
      DWORD  dwYCountChars;
      DWORD  dwFillAttribute;
      DWORD  dwFlags;
      unsigned short wShowWindow;
      unsigned short cbReserved2;
      unsigned char* lpReserved2;
      HANDLE hStdInput;
      HANDLE hStdOutput;
      HANDLE hStdError;
    } STARTUPINFOA, *LPSTARTUPINFOA;

    typedef struct _PROCESS_INFORMATION {
      HANDLE hProcess;
      HANDLE hThread;
      DWORD  dwProcessId;
      DWORD  dwThreadId;
    } PROCESS_INFORMATION, *LPPROCESS_INFORMATION;

    BOOL CreatePipe(HANDLE *hReadPipe, HANDLE *hWritePipe, LPSECURITY_ATTRIBUTES lpPipeAttributes, DWORD nSize);
    BOOL SetHandleInformation(HANDLE hObject, DWORD dwMask, DWORD dwFlags);
    BOOL CloseHandle(HANDLE hObject);
    BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, DWORD *lpNumberOfBytesRead, LPVOID lpOverlapped);

    BOOL CreateProcessA(
      LPCSTR lpApplicationName,
      LPSTR lpCommandLine,
      LPVOID lpProcessAttributes,
      LPVOID lpThreadAttributes,
      BOOL bInheritHandles,
      DWORD dwCreationFlags,
      LPVOID lpEnvironment,
      LPCSTR lpCurrentDirectory,
      LPSTARTUPINFOA lpStartupInfo,
      LPPROCESS_INFORMATION lpProcessInformation
    );

    DWORD WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds);
    BOOL GetExitCodeProcess(HANDLE hProcess, DWORD *lpExitCode);

    static const int HANDLE_FLAG_INHERIT = 0x00000001;
    static const int STARTF_USESTDHANDLES = 0x00000100;
	static const int STARTF_USESHOWWINDOW = 0x00000001;
    static const int CREATE_NO_WINDOW = 0x08000000;
    static const unsigned long INFINITE = 0xFFFFFFFF;
    static const DWORD WAIT_OBJECT_0 = 0x00000000;
]]
end

local function run_cmd_windows(cmdline)

  local kernel32 = ffi.load("kernel32")

  local function check(ok, where)
    if ok == 0 then
      error(where .. " failed")
    end
  end

  -- Pipes para STDOUT e STDERR
  local sa = ffi.new("SECURITY_ATTRIBUTES")
  sa.nLength = ffi.sizeof("SECURITY_ATTRIBUTES")
  sa.bInheritHandle = 1
  sa.lpSecurityDescriptor = nil

  local out_read = ffi.new("HANDLE[1]")
  local out_write = ffi.new("HANDLE[1]")
  local err_read = ffi.new("HANDLE[1]")
  local err_write = ffi.new("HANDLE[1]")

  check(kernel32.CreatePipe(out_read, out_write, sa, 0), "CreatePipe(stdout)")
  check(kernel32.CreatePipe(err_read, err_write, sa, 0), "CreatePipe(stderr)")

  -- Não herdar os lados de leitura no processo filho
  check(kernel32.SetHandleInformation(out_read[0], ffi.C.HANDLE_FLAG_INHERIT, 0), "SetHandleInformation(stdout read)")
  check(kernel32.SetHandleInformation(err_read[0], ffi.C.HANDLE_FLAG_INHERIT, 0), "SetHandleInformation(stderr read)")

  -- STARTUPINFO
  local si = ffi.new("STARTUPINFOA")
  si.cb = ffi.sizeof("STARTUPINFOA")
  si.dwFlags = ffi.C.STARTF_USESTDHANDLES + ffi.C.STARTF_USESHOWWINDOW  -- Add SHOWWINDOW flag
  si.wShowWindow = 0;
  si.hStdInput  = nil
  si.hStdOutput = out_write[0]
  si.hStdError  = err_write[0]

  local pi = ffi.new("PROCESS_INFORMATION")

  -- Monta a linha de comando (precisa ser mutável: LPSTR)
  -- Dica: se for comando do shell, use: cmd.exe /C <comando>
  -- Aqui eu já preparo assim para garantir redirecionamentos, etc.
  local full_cmd = "cmd /C " .. cmdline
  local cmd_cstr = ffi.new("char[?]", #full_cmd + 1)
  ffi.copy(cmd_cstr, full_cmd)

  -- Cria o processo oculto, herdando os handles
  local ok = kernel32.CreateProcessA(
      nil,                      -- app
      cmd_cstr,                 -- command line (mutável)
      nil, nil,                 -- security attrs
      1,                        -- bInheritHandles = TRUE
      ffi.C.CREATE_NO_WINDOW,   -- sem janela
      nil,                      -- env
      nil,                      -- cwd
      si, pi
  )

  -- O processo filho já herdou os writes; o pai pode fechar os writes
  kernel32.CloseHandle(out_write[0]); out_write[0] = nil
  kernel32.CloseHandle(err_write[0]); err_write[0] = nil

  -- Função para drenar um handle até EOF
  local function read_all(h)
    local chunks = {}
    local bufsize = 4096
    local buf = ffi.new("uint8_t[?]", bufsize)
    local read = ffi.new("DWORD[1]")
    while true do
      local ok = kernel32.ReadFile(h, buf, bufsize, read, nil)
      if ok == 0 or read[0] == 0 then
        break
      end
      table.insert(chunks, ffi.string(buf, read[0]))
    end
    return table.concat(chunks)
  end

  -- Lê stdout e stderr
  local stdout_str = read_all(out_read[0])
  local stderr_str = read_all(err_read[0])

  -- Espera o processo terminar
  kernel32.WaitForSingleObject(pi.hProcess, ffi.C.INFINITE)

  -- Exit code
  local code = ffi.new("DWORD[1]")
  kernel32.GetExitCodeProcess(pi.hProcess, code)

  -- Fecha tudo
  if out_read[0] ~= nil then kernel32.CloseHandle(out_read[0]) end
  if err_read[0] ~= nil then kernel32.CloseHandle(err_read[0]) end
  if pi.hThread ~= nil then kernel32.CloseHandle(pi.hThread) end
  if pi.hProcess ~= nil then kernel32.CloseHandle(pi.hProcess) end

  return stdout_str:trim(), stderr_str:trim(), tonumber(code[0])
end

----------------------------------------------------------------
-- POSIX (Linux/macOS) – simples com io.popen (já é “headless”)
----------------------------------------------------------------
local function run_cmd_posix(cmdline)
  local f = io.popen(cmdline .. " 2>&1", "r") -- junta stderr em stdout
  if not f then return nil, "falha ao executar", -1 end
  local out = f:read("*a")
  local _, _, status = f:close()  -- em Lua: true/nil, "exit"/"signal", code
  -- Nem todo Lua retorna code de forma consistente; vamos só entregar -1 se não houver.
  local exit = tonumber(status) or 0
  return (out or ""):trim(), "", exit
end


local function run_cmd(cmdline)
  local stdout, stderr, code;
  if jit and jit.os == "Windows" then
    stdout, stderr, code = run_cmd_windows(cmdline)
  end
  if (stderr ~= "") then
    stdout, stderr, code = run_cmd_posix(cmdline)
  end
  return stdout;
end

return run_cmd;
