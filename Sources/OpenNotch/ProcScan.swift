import Darwin
import Foundation

/// Consulta de processos do próprio usuário via libproc (caminho, pasta atual e tempo de CPU).
enum ProcScan {
    struct Proc {
        let pid: pid_t
        let path: String
    }

    static func all() -> [Proc] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var result: [Proc] = []
        for pid in pids.prefix(Int(count)) where pid > 0 {
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                result.append(Proc(pid: pid, path: String(cString: buffer)))
            }
        }
        return result
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Tempo de CPU acumulado (usuário + sistema), em segundos.
    static func cpuSeconds(of pid: pid_t) -> Double? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        let ticks = Double(usage.ri_user_time + usage.ri_system_time)
        return ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}

extension ProcScan {
    struct Usage {
        let cpuSeconds: Double
        let memory: UInt64      // "footprint", o mesmo número do Monitor de Atividade
    }

    static func usage(of pid: pid_t) -> Usage? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        let ticks = Double(usage.ri_user_time + usage.ri_system_time)
        return Usage(cpuSeconds: ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000,
                     memory: usage.ri_phys_footprint)
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    // Processos auxiliares lançados pelo sistema (ex.: abas do Safari) não são filhos do app,
    // mas o sistema sabe quem é o "responsável" por eles. A função existe na libSystem,
    // só não tem cabeçalho público; se sumir, caímos na árvore de pais.
    private static let responsibleFn: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func responsible(for pid: pid_t) -> pid_t? {
        guard let fn = responsibleFn else { return nil }
        let result = fn(pid)
        return result > 0 ? result : nil
    }
}
