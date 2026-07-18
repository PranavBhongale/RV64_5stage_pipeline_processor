#include <iostream>
#include <fstream>
#include <iomanip>
#include <cstdint>
#include <string>

using namespace std;

enum class DataType
{
    BYTE,
    HALFWORD,
    WORD,
    DWORD
};

class DataAndInstructionMemory
{
public:

    // Instruction Interface

    uint64_t instruction_address = 0;

    bool instruction_valid = false;
    bool instruction_ready = false;

    uint32_t instruction_data = 0;

    
    // Data Interface

    uint64_t data_address = 0;

    uint64_t write_data = 0;
    uint64_t read_data = 0;

    bool read_enable = false;
    bool write_enable = false;

    DataType access_type = DataType::DWORD;

    
    // Status
    

    bool address_alignment_error = false;
    bool address_out_of_range = false;

    // Memory Arrays
    

    static constexpr uint64_t INSTRUCTION_MEMORY_SIZE = 4096;
    static constexpr uint64_t DATA_MEMORY_SIZE = 65536;

    uint32_t instruction_memory[INSTRUCTION_MEMORY_SIZE];
    uint8_t  data_memory[DATA_MEMORY_SIZE];

    // Constructor

    DataAndInstructionMemory()
    {
        for(uint64_t i = 0; i < INSTRUCTION_MEMORY_SIZE; i++)
            instruction_memory[i] = 0;

        for(uint64_t i = 0; i < DATA_MEMORY_SIZE; i++)
            data_memory[i] = 0;

        loadInstructionMemory();
        loadDataMemory();
    }

    // Load Instruction Memory

    void loadInstructionMemory()
    {
        ifstream file("memory\\golden_instruction_memory.hex");

        if(!file.is_open())
        {
            cout << "instruction.hex not found\n";
            return;
        }

        string line;
        uint64_t index = 0;

        while(getline(file, line))
        {
            if(index >= INSTRUCTION_MEMORY_SIZE)
                break;

            instruction_memory[index] =
                static_cast<uint32_t>(
                    stoul(line, nullptr, 16));

            index++;
        }

        file.close();
    }

    
    // Load Data Memory

    void loadDataMemory()
    {
        ifstream file("memory\\golden_data_memory.hex");

        if(!file.is_open())
        {
            cout << "data.hex not found\n";
            return;
        }

        string line;
        uint64_t index = 0;

        while(getline(file, line))
        {
            if(index >= DATA_MEMORY_SIZE)
                break;

            data_memory[index] =
                static_cast<uint8_t>(
                    stoul(line, nullptr, 16));

            index++;
        }

        file.close();
    }

    // Save Data Memory

    void saveDataMemory()
    {
        ofstream file("memory\\golden_data_memory.hex");

        if(!file.is_open())
            return;

        for(uint64_t i = 0; i < DATA_MEMORY_SIZE; i++)
        {
            file << hex
                 << setw(2)
                 << setfill('0')
                 << static_cast<uint32_t>(data_memory[i])
                 << "\n";
        }

        file.close();
    }

    // Save Instruction Memory

    void saveInstructionMemory()
    {
        ofstream file("memory\\golden_instruction_memory.hex");

        if(!file.is_open())
            return;

        for(uint64_t i = 0; i < INSTRUCTION_MEMORY_SIZE; i++)
        {
            file << hex
                 << setw(8)
                 << setfill('0')
                 << instruction_memory[i]
                 << "\n";
        }

        file.close();
    }

    
    // Alignment Check

    bool checkAlignment()
    {
        switch(access_type)
        {
            case DataType::BYTE:
                return true;

            case DataType::HALFWORD:
                return ((data_address & 0x1) == 0);

            case DataType::WORD:
                return ((data_address & 0x3) == 0);

            case DataType::DWORD:
                return ((data_address & 0x7) == 0);

            default:
                return false;
        }
    }

    
    // Bytes Required

    uint64_t getAccessSize()
    {
        switch(access_type)
        {
            case DataType::BYTE:
                return 1;

            case DataType::HALFWORD:
                return 2;

            case DataType::WORD:
                return 4;

            case DataType::DWORD:
                return 8;

            default:
                return 0;
        }
    }

    
    // Range Check

    bool checkRange()
    {
        uint64_t size = getAccessSize();

        return ((data_address + size) <= DATA_MEMORY_SIZE);
    }

    
    // Instruction Memory Tick

    void instructionMemoryTick()
    {
        instruction_ready = true;

        printf("IMEM READ: addr=%llX index=%llu data=%08X\n",
       instruction_address,
       instruction_address/4,
       instruction_data);
        if(!instruction_valid)
            return;

        if((instruction_address & 0x3) != 0)
        {
            cout << "Instruction Address Misaligned\n";
            return;
        }

        uint64_t index = instruction_address >> 2;

        if(index >= INSTRUCTION_MEMORY_SIZE)
        {
            cout << "Instruction Address Out Of Range\n";
            return;
        }

        instruction_data =
            instruction_memory[index];
    }

    // Data Memory Tick
    

    void dataMemoryTick()
    {
        address_alignment_error = false;
        address_out_of_range = false;

        if(!(read_enable || write_enable))
            return;

        if(!checkAlignment())
        {
            address_alignment_error = true;

            cout << "Data Address Misaligned\n";
            return;
        }

        if(!checkRange())
        {
            address_out_of_range = true;

            cout << "Data Address Out Of Range\n";
            return;
        }

        
        // READ
        

        if(read_enable)
        {
            read_data = 0;

            uint64_t bytes = getAccessSize();

            for(uint64_t i = 0; i < bytes; i++)
            {
                read_data |=
                    (static_cast<uint64_t>(
                        data_memory[data_address + i])
                     << (8 * i));
            }
        }

        // WRITE
        

        if(write_enable)
        {
            uint64_t bytes = getAccessSize();

            for(uint64_t i = 0; i < bytes; i++)
            {
                data_memory[data_address + i] =
                    static_cast<uint8_t>(
                        (write_data >> (8 * i)) & 0xFF);
            }
            saveDataMemory();
        }
         for (int i = 0; i < 10; i++)
        {
            printf("IMEM[%d] = %08X\n", i, instruction_memory[i]);
        }
    }
   
};


