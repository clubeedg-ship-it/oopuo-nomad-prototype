#!/usr/bin/env python3
"""
OOPUO Dashboard - Prototype v1.0
A simple TUI that shows system status and provides navigation
"""

import curses
import subprocess
import time
from datetime import datetime

class Dashboard:
    def __init__(self, stdscr):
        self.stdscr = stdscr
        self.height, self.width = stdscr.getmaxyx()
        curses.curs_set(0)  # Hide cursor
        stdscr.nodelay(1)   # Non-blocking input
        stdscr.timeout(1000)  # Refresh every second
        
        # Initialize colors
        curses.start_color()
        curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)
        curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
        curses.init_pair(3, curses.COLOR_YELLOW, curses.COLOR_BLACK)
        curses.init_pair(4, curses.COLOR_RED, curses.COLOR_BLACK)
        
    def get_system_info(self):
        """Gather system metrics"""
        try:
            # CPU info
            cpu_cmd = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
            cpu_usage = subprocess.check_output(cpu_cmd, shell=True).decode().strip()
            
            # Memory info
            mem_cmd = "free | grep Mem | awk '{printf \"%.1f\", $3/$2 * 100}'"
            mem_usage = subprocess.check_output(mem_cmd, shell=True).decode().strip()
            
            # Nomad status
            nomad_cmd = "systemctl is-active nomad 2>/dev/null || echo 'inactive'"
            nomad_status = subprocess.check_output(nomad_cmd, shell=True).decode().strip()
            
            # Nomad jobs count
            jobs_cmd = "nomad job status 2>/dev/null | grep -c 'running' || echo '0'"
            jobs_count = subprocess.check_output(jobs_cmd, shell=True).decode().strip()
            
            return {
                'cpu': float(cpu_usage) if cpu_usage else 0.0,
                'mem': float(mem_usage) if mem_usage else 0.0,
                'nomad': nomad_status,
                'jobs': jobs_count,
                'time': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
        except Exception as e:
            return {
                'cpu': 0.0,
                'mem': 0.0,
                'nomad': 'error',
                'jobs': '0',
                'time': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                'error': str(e)
            }
    
    def draw_header(self):
        """Draw the top header bar"""
        header = "╔═══════════════════════════════════════╗"
        title = "║       OOPUO ENTERPRISE v1.0          ║"
        border = "╚═══════════════════════════════════════╝"
        
        self.stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        self.stdscr.addstr(0, 2, header)
        self.stdscr.addstr(1, 2, title)
        self.stdscr.addstr(2, 2, border)
        self.stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)
        
    def draw_metrics(self, info):
        """Draw system metrics"""
        row = 4
        
        # Time
        self.stdscr.addstr(row, 4, f"⏰ Time: {info['time']}", curses.color_pair(2))
        row += 2
        
        # CPU
        cpu_color = 2 if info['cpu'] < 70 else 3 if info['cpu'] < 90 else 4
        self.stdscr.addstr(row, 4, f"🔥 CPU:  {info['cpu']:5.1f}%", curses.color_pair(cpu_color))
        self.draw_bar(row, 24, info['cpu'], 100)
        row += 1
        
        # Memory
        mem_color = 2 if info['mem'] < 70 else 3 if info['mem'] < 90 else 4
        self.stdscr.addstr(row, 4, f"💾 MEM:  {info['mem']:5.1f}%", curses.color_pair(mem_color))
        self.draw_bar(row, 24, info['mem'], 100)
        row += 2
        
        # Nomad status
        nomad_color = 2 if info['nomad'] == 'active' else 4
        status_icon = "●" if info['nomad'] == 'active' else "○"
        self.stdscr.addstr(row, 4, f"🚀 Nomad: {status_icon} {info['nomad']}", curses.color_pair(nomad_color))
        row += 1
        
        # Jobs count
        self.stdscr.addstr(row, 4, f"📦 Jobs:  {info['jobs']} running", curses.color_pair(2))
        
    def draw_bar(self, row, col, value, max_val):
        """Draw a progress bar"""
        bar_width = 20
        filled = int((value / max_val) * bar_width)
        bar = "█" * filled + "░" * (bar_width - filled)
        self.stdscr.addstr(row, col, f"[{bar}]")
        
    def draw_menu(self):
        """Draw navigation menu"""
        row = self.height - 8
        
        self.stdscr.addstr(row, 4, "╔═══════════════════════╗", curses.color_pair(1))
        row += 1
        self.stdscr.addstr(row, 4, "║    NAVIGATION         ║", curses.color_pair(1))
        row += 1
        self.stdscr.addstr(row, 4, "╠═══════════════════════╣", curses.color_pair(1))
        row += 1
        self.stdscr.addstr(row, 4, "║  [N] Nomad UI         ║")
        row += 1
        self.stdscr.addstr(row, 4, "║  [J] List Jobs        ║")
        row += 1
        self.stdscr.addstr(row, 4, "║  [L] View Logs        ║")
        row += 1
        self.stdscr.addstr(row, 4, "║  [Q] Quit             ║")
        row += 1
        self.stdscr.addstr(row, 4, "╚═══════════════════════╝", curses.color_pair(1))
        
    def draw_footer(self):
        """Draw footer"""
        footer = "[ OOPUO Enterprise | Privacy-First AI Infrastructure ]"
        self.stdscr.attron(curses.color_pair(1))
        self.stdscr.addstr(self.height - 1, 2, footer)
        self.stdscr.attroff(curses.color_pair(1))
        
    def handle_input(self, key):
        """Handle user input"""
        if key == ord('q') or key == ord('Q'):
            return False
        elif key == ord('n') or key == ord('N'):
            self.show_message("Nomad UI: http://localhost:4646")
            time.sleep(3)
        elif key == ord('j') or key == ord('J'):
            self.show_jobs()
        elif key == ord('l') or key == ord('L'):
            self.show_logs()
        return True
    
    def show_message(self, msg):
        """Show a temporary message"""
        row = self.height // 2
        col = (self.width - len(msg)) // 2
        self.stdscr.addstr(row, col, msg, curses.color_pair(3) | curses.A_BOLD)
        self.stdscr.refresh()
    
    def show_jobs(self):
        """Show Nomad jobs"""
        curses.endwin()
        subprocess.run("nomad job status", shell=True)
        print("\nPress ENTER to continue...")
        input()
        self.stdscr = curses.initscr()
        curses.start_color()
        self.init_colors()
        
    def show_logs(self):
        """Show recent logs"""
        curses.endwin()
        subprocess.run("journalctl -u nomad -n 50 --no-pager", shell=True)
        print("\nPress ENTER to continue...")
        input()
        self.stdscr = curses.initscr()
        curses.start_color()
        self.init_colors()
    
    def init_colors(self):
        """Initialize color pairs"""
        curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)
        curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
        curses.init_pair(3, curses.COLOR_YELLOW, curses.COLOR_BLACK)
        curses.init_pair(4, curses.COLOR_RED, curses.COLOR_BLACK)
        
    def run(self):
        """Main event loop"""
        running = True
        
        while running:
            try:
                self.stdscr.clear()
                
                # Get fresh data
                info = self.get_system_info()
                
                # Draw UI
                self.draw_header()
                self.draw_metrics(info)
                self.draw_menu()
                self.draw_footer()
                
                # Refresh screen
                self.stdscr.refresh()
                
                # Handle input
                key = self.stdscr.getch()
                if key != -1:
                    running = self.handle_input(key)
            except KeyboardInterrupt:
                running = False
            except Exception as e:
                # Graceful error handling
                pass

def main(stdscr):
    dashboard = Dashboard(stdscr)
    dashboard.run()

if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        print("\nGoodbye!")
