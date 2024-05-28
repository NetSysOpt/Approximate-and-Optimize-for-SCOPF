# SCOPF surrogate 
1. generate the scenario data
2. evaluate the solutions to generate the training data for the approximation network

The evaluation of the solutions is done by the `evaluate.py` and `data.py` script. The script is based on https://github.com/GOCompetition/Evaluation.git

## Repository structure
```
- src
    - generate_data.py  \\generate the scenario data
    - random_load_profile.py    \\generate the random load profile
    - generate_data_parallel.py and scenario_operations.py  \\used to generate the scenario data in parallel
    - get_stage2_pen.py     \\gather the second stage penalty from each detail file, and splitting the data for training the approximation neural network.
    - generate_result.py    \\generate solving time and solution results into the the ./result folder
- model
    folder to store the trained model weights
- result    \\store the result csv files
    - result.ipynb and time_result.ipynb    \\generate the result table and plots
- load_model.py     \\load the trained model and write the weights of the neural network in to txt files in the model folder
- test.py, test.sh      \\the function to call the evalutation.run method to evaluate the solutions
- examples
    - case2 # an example datafile 
```

## Generate scenarios
```
python generate_data.py

python random_load_profile.py
```

## Get the penalization for collected base case solutions
```
bash test.sh
python get_stage2_pen.py
```

## Train the model
```
python approx_model.py
```