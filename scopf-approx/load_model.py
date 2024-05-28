'''
load the trained neural network and write the weights to txt files
'''
import torch
from approx_model import ApproxNet


DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
learning_rate = 0.0005
batch_size = 64
NUM_HIDDEN_LIST = [16, 64]
log_dir = "./model/weights/"
print(f'log_dir: {log_dir}')
print("using device: ", DEVICE)
input_dim = 1502 # 2840, 502
approx_net = ApproxNet(learning_rate, log_dir, input_dim, NUM_HIDDEN_LIST)
approx_net.load("best")

def save_to_txt(filename, array):
    with open(filename, 'w') as f:
        for val in array.flatten():
            f.write(f"{val}\n")


for name, param in approx_net._network.named_parameters():
    filename = log_dir + name.split(".")[1] + "_" + name.split(".")[2] + ".txt"
    save_to_txt(filename, param.data.cpu())