# Retro Highway Racer (MASM + Irvine32)

Using mainly MASM, the goal is to make a top-down ASCII retro highway racing game that randomly places obstacles in the highway stream at a set interval & speed. Score climbs with time and speed. 

**Gameplay Overview**
- Goal: Stay alive by avoiding obstacles in the road while your score increases over time.
- View: Top-down highway.road rendered in CMD.
- Player: ASCII car or small sprite.
- Obstacles: Randomly spawn in lanes and scroll downward.
- Difficulty: Speed and spawn rate can ramp up.
- Game Over: When car hits an obstacle, high score saved in memory

**Controls**
- Left Arrow: Move one lane left
- Right Arrow: Move one lane right
- Esc: X

**Running Intructions**
- Download the GitHub
- Open the correct Project32_VS for your version of Visual Studio
- Copy the .asm file and paste it into the project folder
- Add existing file to the now open project
- Build the .asm file
- Open the project folder and open the Debug folder
- Copy its path
- Open Windows Command Prompt
- Change directory to the copied path (cd ../Debug)
- Input the command: chcp 1252 (this allows certain characters to show up)
- Then run the .exe file by using the command: Project.exe

**Credits**
- Team: Jacob Carton & Matthew Goembel
- Instructor: Dr. Silaghi
- Libraries: Irvine32

**Screenshot**
![Screenshot](screenshot.png)
