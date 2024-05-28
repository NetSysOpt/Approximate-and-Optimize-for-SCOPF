"""model to approximate the single second stage cost"""
import argparse
import os
from collections import OrderedDict
from collections import namedtuple

import numpy as np
import pandas as pd
import torch
from torch import nn
from torch.utils import tensorboard
from torch.utils.data import DataLoader, Dataset
import torch.nn.utils.prune as prune
import numpy as np

torch.manual_seed(42)
DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
SUMMARY_INTERVAL = 100
SAVE_INTERVAL = 50
PRINT_INTERVAL = 100
VAL_INTERVAL = 50

class ThresholdPruning(prune.BasePruningMethod):
    PRUNING_TYPE = "unstructured"

    def __init__(self, threshold):
        super().__init__()
        self.threshold = threshold

    def compute_mask(self, tensor, default_mask):
        return torch.abs(tensor) > self.threshold


class ApproxDataset(Dataset):
    def __init__(self, file_path):
        # convert into PyTorch tensors and remember them
        df = pd.read_csv(file_path)
        if "train" in file_path:
            df = df.iloc[:5000]
        if "val" in file_path:
            df = df.iloc[:1500]
        self.X = df[df.columns[:-1]].values
        self.y = np.log(df[['stage2_pen']].values)
        self.X = torch.tensor(self.X, dtype=torch.float32)
        self.y = torch.tensor(self.y, dtype=torch.float32)

    def __len__(self):
        return len(self.X)

    def __getitem__(self, idx):
        features = self.X[idx]
        target = self.y[idx]
        return features, target


class ApproxNetwork(nn.Module):
    def __init__(self, input_dim, num_hidden_list, l1_lambda=0.0):
        super(ApproxNetwork, self).__init__()
        self.num_hidden_list = num_hidden_list
        prev_hidden = input_dim
        dic = []
        for i, hidden in enumerate(self.num_hidden_list):
            dic.append((f'linear{i}', nn.Linear(prev_hidden, hidden, bias=True)))
            dic.append((f'activation{i}', nn.GELU()))
            prev_hidden = hidden

        dic.append((f'linear{len(self.num_hidden_list)}', nn.Linear(prev_hidden, 1, bias=True)))
        # dic.append((f'activation{len(self.num_hidden_list)}', nn.Softplus()))
        self.net = nn.Sequential(OrderedDict(dic))

        for name, param in self.net.named_parameters():
            if "weight" in name:
                nn.init.xavier_uniform_(param)

        self.to(DEVICE)
        self.l1_lambda = l1_lambda

    def forward(self, x):
        return self.net(x)

    def l1_regularization(self):
        l1_loss = 0.0
        for name, param in self.named_parameters():
            if "bias" not in name:
                l1_loss += torch.norm(param, p=1)
        return self.l1_lambda * l1_loss


class ApproxNet:
    def __init__(self, learning_rate, log_dir, input_dim, num_hidden_list, l1_lambda=0.0, l2_lambda=0.0, grad_pen=0.0):
        self._network = ApproxNetwork(input_dim, num_hidden_list, l1_lambda)
        self._optimizer = torch.optim.Adam(
            self._network.parameters(),
            lr=learning_rate,
            weight_decay=l2_lambda
        )
        self._log_dir = log_dir
        os.makedirs(self._log_dir, exist_ok=True)

        self._start_train_step = 0
        self._criterion = nn.HuberLoss()
        self.l1_lambda = l1_lambda
        self.l2_lambda = l2_lambda
        self.grad_pen = grad_pen
        print(f'created approxnet with l1_lambda: {l1_lambda}, l2_lambda: {l2_lambda}, grad_pen: {grad_pen}')

    def _step(self, X, y):
        X = X.to(DEVICE)
        y = y.to(DEVICE)
        return self._criterion(self._network(X), y)

    def train(self, dataloader_train, dataloader_val, writer, num_epochs):
        print(f'Starting training at epoch {self._start_train_step}.')
        best_val = float('inf')
        for epoch in range(self._start_train_step, self._start_train_step + num_epochs):
            losses = []
            grads = []
            for X, y in dataloader_train:
                self._optimizer.zero_grad()
                loss = self._step(X, y)
                
                if self.grad_pen > 0.0:
                    input_tensor = X.clone().requires_grad_(True).to(DEVICE)
                    output_tensor = self._network(input_tensor)
                    gradients = torch.autograd.grad(outputs=output_tensor, inputs=input_tensor, grad_outputs=torch.ones_like(output_tensor), create_graph=True)[0]
                    penalty = torch.mean(torch.sum(gradients ** 2, dim=1))
                    if epoch % 1000 == 0:
                        print(f'epoch: {epoch}, loss: {loss.item()}, penalty: {penalty.item()}')
                    loss += self.grad_pen * penalty
                    grads.append(penalty.item())
                
                losses.append(loss.item())
                
                if self.l1_lambda > 0.0:
                    loss += self._network.l1_regularization()

                loss.backward()
                self._optimizer.step()

            if epoch % PRINT_INTERVAL == 0:
                print(
                    f'Epoch {epoch}: '
                    f'loss: {np.mean(losses):.6f} '
                )
                writer.add_scalar('loss/train', np.mean(losses), epoch)
                if len(grads) > 0:
                    writer.add_scalar('grad/train', np.mean(grads), epoch)

            if epoch % VAL_INTERVAL == 0 and epoch > 0:
                with torch.no_grad():
                    losses_val = []
                    for X, y in dataloader_val:
                        losses_val.append(self._step(X, y).item())
                    loss_val = np.mean(losses_val)
                print(
                    f'Validation: '
                    f'loss: {loss_val:.6f} '
                )
                writer.add_scalar('loss/val', loss_val, epoch)
                if loss_val < best_val:
                    best_val = loss_val
                    self._save("best")
                    print(f'New best validation loss: {best_val:.3f}')

            if epoch % SAVE_INTERVAL == 0:
                self._save(epoch)
        if self.l1_lambda > 0.0 or self.l2_lambda > 0.0:
            self.prune()


    def test(self, dataloader_test):
        """Evaluate the ProtoNet on test tasks.
        Args:
            dataloader_test (DataLoader): loader for test tasks
        """
        losses = []
        for X, y in dataloader_test:
            losses.append(self._step(X, y).item())
        mean = np.mean(losses)
        std = np.std(losses)
        mean_95_confidence_interval = 1.96 * std / np.sqrt(len(dataloader_test))
        print(
            f'Loss over test dataset: '
            f'mean {mean:.3f}, '
            f'95% confidence interval {mean_95_confidence_interval:.3f}'
        )

    def load(self, checkpoint_step):
        """Loads a checkpoint.

        Args:
            checkpoint_step: iteration of checkpoint to load

        Raises:
            ValueError: if checkpoint for checkpoint_step is not found
        """
        target_path = (
            f'{os.path.join(self._log_dir, "state_")}'
            f'{checkpoint_step}.pt'
        )
        if os.path.isfile(target_path):
            if DEVICE == "cuda":
                state = torch.load(target_path)
            else:
                state = torch.load(target_path, map_location=torch.device('cpu'))
            self._network.load_state_dict(state['network_state_dict'])
            self._optimizer.load_state_dict(state['optimizer_state_dict'])
            if isinstance(checkpoint_step, int):
                self._start_train_step = checkpoint_step + 1
            print(f'Loaded checkpoint iteration {checkpoint_step}.')
        else:
            raise ValueError(
                f'No checkpoint for iteration {checkpoint_step} found.'
            )

    def _save(self, checkpoint_step):
        """Saves network and optimizer state_dicts as a checkpoint.
        checkpoint_step can be replaced as any string
        - if int, then save as state123.pt
        - if string, then save as state{string}.pt

        Args:
            checkpoint_step: iteration to label checkpoint with
        """
        torch.save(
            dict(network_state_dict=self._network.state_dict(),
                 optimizer_state_dict=self._optimizer.state_dict()),
            f'{os.path.join(self._log_dir, "state_")}{checkpoint_step}.pt'
        )
        print('Saved checkpoint.')

    def prune(self, threshold=1e-4, postfix="pruned"):
        self.load("best")
        parameters_to_prune = ((self._network.net.linear0, "weight"), (self._network.net.linear0, "bias"))
        prune.global_unstructured(
            parameters_to_prune, pruning_method=ThresholdPruning, threshold=threshold
        )
        prune.remove(self._network.net.linear0, name="weight")
        prune.remove(self._network.net.linear0, name="bias")

        self._save(postfix)


def main(args):
    learning_rate = args.learning_rate
    batch_size = args.batch_size
    log_dir = args.log_dir
    epochs = args.epoch
    num_hidden_list = args.hidden
    l1_lambda = args.l1_lambda
    l2_lambda = args.l2_lambda
    grad_pen = args.grad_pen

    if log_dir is None:
        log_dir = './logs/'
    else:
        if log_dir[-1] != "/":
            log_dir += "/"
    log_dir = log_dir + f'gen.lr:{learning_rate}.batch_size:{batch_size}.l1_lambda:{l1_lambda}.l2_lambda:{l2_lambda}.grad_pen:{grad_pen}.hidden:' + "_".join(
            [str(i) for i in num_hidden_list])
    print(f'log_dir: {log_dir}')
    print("using device: ", DEVICE)

    input_dim = 1502
    approx_net = ApproxNet(learning_rate, log_dir, input_dim, num_hidden_list, l1_lambda, l2_lambda, grad_pen)

    if args.checkpoint_step > -1:
        approx_net.load(args.checkpoint_step)
    else:
        if args.test:
            approx_net.load("best")
        else:
            print('Checkpoint loading skipped.')

    writer = tensorboard.SummaryWriter(log_dir=log_dir)

    train_file = "./data/stage2_pen_train.csv"
    val_file = "./data/stage2_pen_val.csv"
    test_file = "./data/stage2_pen_test.csv"

    if not args.test:
        dataset_train = ApproxDataset(train_file)
        dataset_val = ApproxDataset(val_file)
        print(f'Training dataset: {len(dataset_train)}')
        print(f'Validation dataset: {len(dataset_val)}')
        dataloader_train = DataLoader(dataset_train, batch_size=batch_size, shuffle=True)
        dataloader_val = DataLoader(dataset_val, batch_size=batch_size, shuffle=True)
        approx_net.train(dataloader_train, dataloader_val, writer, num_epochs=epochs)
    else:
        dataloader_test = DataLoader(ApproxDataset(test_file), batch_size=batch_size, shuffle=True)
        # approx_net.prune()
        approx_net.test(dataloader_test)


def parse_list(input_str):
    try:
        return [int(item) for item in input_str.split(',')]
    except ValueError as e:
        raise argparse.ArgumentTypeError(f"Invalid list format: {e}")


if __name__ == "__main__":
    Arguments = namedtuple("Arguments", ["log_dir", "learning_rate", "batch_size", "epoch", "test", "checkpoint_step", 
                                         "hidden", "l1_lambda", "l2_lambda", "grad_pen"])

    log_dir = "log/"
    learning_rate = 0.0003
    batch_size = 64
    epoch = 1000
    test = False
    checkpoint_step = -1

    hidden_list = [[16, 64]]

    l1_lambda_list = [0.0]
    # l1_lambda_list = [0.0]
    l2_lambda_list = [1e-3]
    grad_pen_list = [0.0]

    for hidden in hidden_list:
        for grad_pen in grad_pen_list:
            for l1_lambda in l1_lambda_list:
                for l2_lambda in l2_lambda_list:
                    args = Arguments(log_dir=log_dir, learning_rate=learning_rate, batch_size=batch_size, epoch=epoch, test=test, checkpoint_step=checkpoint_step, 
                                     hidden=hidden, l1_lambda=l1_lambda, l2_lambda=l2_lambda, grad_pen=grad_pen)
                    main(args)
