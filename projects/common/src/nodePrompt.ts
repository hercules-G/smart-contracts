import * as readline from "readline";

// Define an async function to read user input
const readUserInput = async (prompt: string): Promise<string> => {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(prompt, (input) => {
      rl.close(); // Close the readline interface after getting the input
      resolve(input);
    });
  });
};

// Export the function as the default export
export default readUserInput;
